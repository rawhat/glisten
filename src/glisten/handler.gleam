import gleam/bit_builder.{BitBuilder}
import gleam/dynamic
import gleam/erlang/atom
import gleam/erlang/process.{Subject}
import gleam/function
import gleam/option.{Option, Some}
import gleam/otp/actor
import gleam/otp/port.{Port}
import gleam/result
import gleam/string
import glisten/logger
import glisten/socket.{Socket}
import glisten/socket/transport.{Transport}
import glisten/socket/options

/// All message types that the handler will receive, or that you can
/// send to the handler process
pub type HandlerMessage {
  Close
  Ready
  ReceiveMessage(BitString)
  SendMessage(BitBuilder)
  Ssl(socket: Port, data: BitString)
  SslClosed
  Tcp(socket: Port, data: BitString)
  TcpClosed
}

pub type ClientIp =
  Result(#(#(Int, Int, Int, Int), Int), Nil)

pub type LoopState(data) {
  LoopState(
    client_ip: ClientIp,
    socket: Socket,
    sender: Subject(HandlerMessage),
    transport: Transport,
    data: data,
  )
}

pub type LoopFn(data) =
  fn(HandlerMessage, LoopState(data)) -> actor.Next(LoopState(data))

pub type Handler(data) {
  Handler(
    socket: Socket,
    initial_data: data,
    loop: LoopFn(data),
    on_init: Option(fn(Subject(HandlerMessage)) -> Nil),
    on_close: Option(fn(Subject(HandlerMessage)) -> Nil),
    transport: Transport,
  )
}

/// Starts an actor for the TCP connection
pub fn start(
  handler: Handler(data),
) -> Result(Subject(HandlerMessage), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let subject = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting_record3(
          atom.create_from_string("tcp"),
          fn(_sock, data) {
            data
            |> dynamic.bit_string
            |> result.unwrap(<<>>)
            |> ReceiveMessage
          },
        )
        |> process.selecting_record3(
          atom.create_from_string("ssl"),
          fn(_sock, data) {
            data
            |> dynamic.bit_string
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
        |> process.selecting(subject, function.identity)

      actor.Ready(
        LoopState(
          client_ip: peername(handler.socket),
          socket: handler.socket,
          sender: subject,
          transport: handler.transport,
          data: handler.initial_data,
        ),
        selector,
      )
    },
    init_timeout: 1000,
    loop: fn(msg, state) {
      case msg {
        TcpClosed | SslClosed | Close ->
          case state.transport.close(state.socket) {
            Ok(Nil) -> {
              let _ = case handler.on_close {
                Some(on_close) -> on_close(state.sender)
                _ -> Nil
              }
              actor.Stop(process.Normal)
            }
            Error(err) -> actor.Stop(process.Abnormal(string.inspect(err)))
          }
        Ready ->
          state.socket
          |> state.transport.handshake
          |> result.replace_error("Failed to handshake socket")
          |> result.map(fn(_ok) {
            let _ = case handler.on_init {
              Some(on_init) -> on_init(state.sender)
              _ -> Nil
            }
          })
          |> result.then(fn(_ok) {
            state.transport.set_opts(
              state.socket,
              [options.ActiveMode(options.Once)],
            )
            |> result.replace_error("Failed to set socket active")
          })
          |> result.replace(actor.Continue(state))
          |> result.map_error(fn(reason) {
            actor.Stop(process.Abnormal(reason))
          })
          |> result.unwrap_both
        msg ->
          case handler.loop(msg, state) {
            actor.Continue(next_state) -> {
              let assert Ok(Nil) =
                state.transport.set_opts(
                  state.socket,
                  [options.ActiveMode(options.Once)],
                )
              actor.Continue(next_state)
            }
            msg -> msg
          }
      }
    },
  ))
}

pub type HandlerFunc(data) =
  fn(BitString, LoopState(data)) -> actor.Next(LoopState(data))

/// This helper will generate a TCP handler that will call your handler function
/// with the BitString data in the packet as well as the LoopState, with any
/// associated state data you are maintaining
pub fn func(handler func: HandlerFunc(data)) -> LoopFn(data) {
  fn(msg, state: LoopState(data)) {
    case msg {
      Tcp(_, _) | Ready -> {
        logger.error(#("Received an unexpected TCP message", msg))
        actor.Continue(state)
      }
      ReceiveMessage(data) -> func(data, state)
      SendMessage(data) ->
        case state.transport.send(state.socket, data) {
          Ok(_nil) -> actor.Continue(state)
          Error(reason) -> {
            logger.error(#("Failed to send data", reason))
            actor.Stop(process.Abnormal("Failed to send data"))
          }
        }
      // NOTE:  this should never happen.  This function is only called _after_
      // the other message types are handled
      msg -> {
        logger.error(#("Unhandled TCP message", msg))
        actor.Stop(process.Abnormal("Unhandled TCP message"))
      }
    }
  }
}

@external(erlang, "inet", "peername")
fn peername(socket: Socket) -> Result(#(#(Int, Int, Int, Int), Int), Nil)
