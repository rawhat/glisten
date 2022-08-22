import gleam/bit_builder.{BitBuilder}
import gleam/dynamic
import gleam/erlang/process.{Subject}
import gleam/function
import gleam/option.{Option, Some}
import gleam/otp/actor
import gleam/otp/port.{Port}
import glisten/logger
import glisten/socket.{Socket}
import glisten/tcp
import glisten/tcp/options

/// All message types that the handler will receive, or that you can
/// send to the handler process
pub type HandlerMessage {
  Close
  Ready
  ReceiveMessage(BitString)
  SendMessage(BitBuilder)
  Tcp(socket: Port, data: BitString)
  TcpClosed(Nil)
}

pub type LoopState(data) {
  LoopState(socket: Socket, sender: Subject(HandlerMessage), data: data)
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
        |> process.selecting(subject, function.identity)
        |> process.selecting_anything(fn(msg) {
          case dynamic.unsafe_coerce(msg) {
            Tcp(_sock, data) -> ReceiveMessage(data)
            msg -> msg
          }
        })
      let _ = case handler.on_init {
        Some(func) -> func(subject)
        _ -> Nil
      }
      actor.Ready(
        LoopState(handler.socket, subject, data: handler.initial_data),
        selector,
      )
    },
    init_timeout: 1_000,
    loop: fn(msg, state) {
      case msg {
        TcpClosed(_) | Close -> {
          tcp.close(state.socket)
          let _ = case handler.on_close {
            Some(func) -> func(state.sender)
            _ -> Nil
          }
          actor.Stop(process.Normal)
        }
        Ready -> {
          assert Ok(_) =
            tcp.set_opts(state.socket, [options.ActiveMode(options.Once)])
          actor.Continue(state)
        }
        msg ->
          case handler.loop(msg, state) {
            actor.Continue(next_state) -> {
              assert Ok(Nil) =
                tcp.set_opts(state.socket, [options.ActiveMode(options.Once)])
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
pub fn handler(handler func: HandlerFunc(data)) -> LoopFn(data) {
  fn(msg, state: LoopState(data)) {
    case msg {
      Tcp(_, _) | Ready -> {
        logger.error(#("Received an unexpected TCP message", msg))
        actor.Continue(state)
      }
      ReceiveMessage(data) -> func(data, state)
      SendMessage(data) ->
        case tcp.send(state.socket, data) {
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
