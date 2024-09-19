import gleam/dynamic
import gleam/erlang.{rescue}
import gleam/erlang/atom
import gleam/erlang/process.{type Selector, type Subject}
import gleam/function
import gleam/option.{type Option, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten/socket.{type Socket}
import glisten/socket/options.{type IpAddress}
import glisten/transport.{type Transport}
import logging

/// All message types that the handler will receive, or that you can
/// send to the handler process
pub type InternalMessage {
  Close
  Ready
  ReceiveMessage(BitArray)
  SslClosed
  TcpClosed
}

pub type Message(user_message) {
  Internal(InternalMessage)
  User(user_message)
}

pub type LoopMessage(user_message) {
  Packet(BitArray)
  Custom(user_message)
}

pub type ClientIp =
  Result(#(IpAddress, Int), Nil)

pub type LoopState(user_message, data) {
  LoopState(
    client_ip: ClientIp,
    socket: Socket,
    sender: Subject(Message(user_message)),
    transport: Transport,
    data: data,
  )
}

pub type Connection(user_message) {
  Connection(
    client_ip: ClientIp,
    socket: Socket,
    transport: Transport,
    sender: Subject(Message(user_message)),
  )
}

pub type Loop(user_message, data) =
  fn(LoopMessage(user_message), data, Connection(user_message)) ->
    actor.Next(LoopMessage(user_message), data)

pub type Handler(user_message, data) {
  Handler(
    socket: Socket,
    loop: Loop(user_message, data),
    on_init: fn(Connection(user_message)) ->
      #(data, Option(Selector(user_message))),
    on_close: Option(fn(data) -> Nil),
    transport: Transport,
  )
}

/// Starts an actor for the TCP connection
pub fn start(
  handler: Handler(user_message, data),
) -> Result(Subject(Message(user_message)), actor.StartError) {
  actor.start_spec(
    actor.Spec(
      init: fn() {
        let subject = process.new_subject()
        let client_ip =
          transport.peername(handler.transport, handler.socket)
          |> result.nil_error
        let connection =
          Connection(
            socket: handler.socket,
            client_ip: client_ip,
            transport: handler.transport,
            sender: subject,
          )
        let #(initial_state, user_selector) = handler.on_init(connection)
        let selector =
          process.new_selector()
          |> process.selecting_record3(
            atom.create_from_string("tcp"),
            fn(_sock, data) {
              data
              |> dynamic.bit_array
              |> result.unwrap(<<>>)
              |> ReceiveMessage
            },
          )
          |> process.selecting_record3(
            atom.create_from_string("ssl"),
            fn(_sock, data) {
              data
              |> dynamic.bit_array
              |> result.unwrap(<<>>)
              |> ReceiveMessage
            },
          )
          |> process.selecting_record2(
            atom.create_from_string("ssl_closed"),
            fn(_nil) { SslClosed },
          )
          |> process.selecting_record2(
            atom.create_from_string("tcp_closed"),
            fn(_nil) { TcpClosed },
          )
          |> process.map_selector(Internal)
          |> process.selecting(subject, function.identity)
        let selector = case user_selector {
          Some(sel) ->
            sel
            |> process.map_selector(User)
            |> process.merge_selector(selector, _)
          _ -> selector
        }
        actor.Ready(
          LoopState(
            client_ip: client_ip,
            socket: handler.socket,
            sender: subject,
            transport: handler.transport,
            data: initial_state,
          ),
          selector,
        )
      },
      init_timeout: 1000,
      loop: fn(msg, state) {
        let connection =
          Connection(
            socket: state.socket,
            client_ip: state.client_ip,
            transport: state.transport,
            sender: state.sender,
          )
        case msg {
          Internal(TcpClosed) | Internal(SslClosed) | Internal(Close) ->
            case transport.close(state.transport, state.socket) {
              Ok(Nil) -> {
                let _ = case handler.on_close {
                  Some(on_close) -> on_close(state.data)
                  _ -> Nil
                }
                actor.Stop(process.Normal)
              }
              Error(err) -> actor.Stop(process.Abnormal(string.inspect(err)))
            }
          Internal(Ready) ->
            state.socket
            |> transport.handshake(state.transport, _)
            |> result.replace_error("Failed to handshake socket")
            |> result.then(fn(_ok) {
              let _ =
                transport.set_buffer_size(state.transport, state.socket)
                |> result.map_error(fn(err) {
                  logging.log(
                    logging.Warning,
                    "Failed to read `recbuf` size, using default: "
                      <> string.inspect(err),
                  )
                })
              Ok(Nil)
            })
            |> result.then(fn(_ok) {
              transport.set_opts(state.transport, state.socket, [
                options.ActiveMode(options.Once),
              ])
              |> result.replace_error("Failed to set socket active")
            })
            |> result.replace(actor.continue(state))
            |> result.map_error(fn(reason) {
              actor.Stop(process.Abnormal(reason))
            })
            |> result.unwrap_both

          User(msg) -> {
            let msg = Custom(msg)
            let res = rescue(fn() { handler.loop(msg, state.data, connection) })
            case res {
              Ok(actor.Continue(next_state, _selector)) -> {
                let assert Ok(Nil) =
                  transport.set_opts(state.transport, state.socket, [
                    options.ActiveMode(options.Once),
                  ])
                actor.continue(LoopState(..state, data: next_state))
              }
              Ok(actor.Stop(reason)) -> actor.Stop(reason)
              Error(reason) -> {
                logging.log(
                  logging.Error,
                  "Caught error in user handler: " <> string.inspect(reason),
                )
                actor.continue(state)
              }
            }
          }
          Internal(ReceiveMessage(msg)) -> {
            let msg = Packet(msg)
            let res = rescue(fn() { handler.loop(msg, state.data, connection) })
            case res {
              Ok(actor.Continue(next_state, _selector)) -> {
                let assert Ok(Nil) =
                  transport.set_opts(state.transport, state.socket, [
                    options.ActiveMode(options.Once),
                  ])
                actor.continue(LoopState(..state, data: next_state))
              }
              Ok(actor.Stop(reason)) -> actor.Stop(reason)
              Error(reason) -> {
                logging.log(
                  logging.Error,
                  "Caught error in user handler: " <> string.inspect(reason),
                )
                actor.continue(state)
              }
            }
          }
        }
      },
    ),
  )
}
