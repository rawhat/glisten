import gleam/erlang/process.{type Selector, type Subject, Abnormal}
import gleam/function
import gleam/list
import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result
import gleam/string
import glisten/internal/handler.{
  type Connection, type Loop, Handler, Internal, Ready,
}
import glisten/internal/listener
import glisten/socket.{type ListenSocket, type Socket}
import glisten/socket/options.{type TcpOption}
import glisten/transport.{type Transport}
import logging

pub type AcceptorMessage {
  AcceptConnection(ListenSocket)
}

pub type AcceptorError {
  AcceptError
  HandlerError
  ControlError
}

pub type AcceptorState {
  AcceptorState(
    sender: Subject(AcceptorMessage),
    socket: Option(Socket),
    transport: Transport,
  )
}

/// Worker process that handles `accept`ing connections and starts a new process
/// which receives the messages from the socket
pub fn start(
  pool: Pool(user_message, data),
  listener: Subject(listener.Message),
) -> Result(Subject(AcceptorMessage), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let subject = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(subject, function.identity)

      process.try_call(listener, listener.Info, 750)
      |> result.map(fn(state) {
        process.send(subject, AcceptConnection(state.listen_socket))
        actor.Ready(AcceptorState(subject, None, pool.transport), selector)
      })
      |> result.map_error(fn(err) {
        actor.Failed("Failed to read listen socket: " <> string.inspect(err))
      })
      |> result.unwrap_both
    },
    // TODO:  rethink this value, probably...
    init_timeout: 1000,
    loop: fn(msg, state) {
      let AcceptorState(sender, ..) = state
      case msg {
        AcceptConnection(listener) -> {
          let res = {
            use sock <- result.then(
              transport.accept(state.transport, listener)
              |> result.replace_error(AcceptError),
            )
            use start <- result.then(
              Handler(
                socket: sock,
                loop: pool.handler,
                on_init: pool.on_init,
                on_close: pool.on_close,
                transport: pool.transport,
              )
              |> handler.start
              |> result.replace_error(HandlerError),
            )
            sock
            |> transport.controlling_process(
              state.transport,
              _,
              process.subject_owner(start),
            )
            |> result.replace_error(ControlError)
            |> result.map(fn(_) { process.send(start, Internal(Ready)) })
          }
          case res {
            Error(reason) -> {
              logging.log(
                logging.Error,
                "Failed to accept/start handler: " <> string.inspect(reason),
              )
              actor.Stop(Abnormal("Failed to accept/start handler"))
            }
            _val -> {
              actor.send(sender, AcceptConnection(listener))
              actor.continue(state)
            }
          }
        }
      }
    },
  ))
}

pub type Pool(user_message, data) {
  Pool(
    handler: Loop(user_message, data),
    pool_count: Int,
    on_init: fn(Connection(user_message)) ->
      #(data, Option(Selector(user_message))),
    on_close: Option(fn(data) -> Nil),
    transport: Transport,
  )
}

/// Starts a pool of acceptors of size `pool_count`.
///
/// Runs `loop_fn` on ever message received
pub fn start_pool(
  pool: Pool(user_message, data),
  transport: Transport,
  port: Int,
  options: List(TcpOption),
  return: Subject(Subject(listener.Message)),
) -> Result(Subject(supervisor.Message), actor.StartError) {
  supervisor.start_spec(supervisor.Spec(
    argument: Nil,
    // TODO:  i think these might need some tweaking
    max_frequency: 100,
    frequency_period: 1,
    init: fn(children) {
      let acceptors = list.range(from: 0, to: pool.pool_count)
      supervisor.add(
        children,
        supervisor.worker(fn(_arg) {
          listener.start(port, transport, options)
          |> result.map(fn(subj) {
            process.send(return, subj)
            subj
          })
        })
          |> supervisor.returning(fn(_prev, listener) { listener }),
      )
      |> list.fold(
        acceptors,
        _,
        fn(children, _index) {
          supervisor.add(
            children,
            supervisor.worker(fn(listener) { start(pool, listener) }),
          )
        },
      )
    },
  ))
}
