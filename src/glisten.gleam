import gleam/bit_builder
import gleam/dynamic.{Dynamic}
import gleam/erlang/process
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result
import glisten/acceptor.{AcceptorState, Pool}
import glisten/handler.{HandlerMessage, ReceiveMessage}
import glisten/socket.{Closed, ListenSocket, Timeout}
import glisten/tcp

/// Reasons that `serve` might fail
pub type StartError {
  ListenerClosed
  ListenerTimeout
  AcceptorTimeout
  AcceptorFailed(process.ExitReason)
  AcceptorCrashed(Dynamic)
}

/// Sets up a TCP listener with the given acceptor pool. The second argument
/// can be obtained from the `glisten/tcp.{acceptor_pool}` function.
pub fn serve(
  port: Int,
  with_pool: fn(ListenSocket) -> Pool(data),
) -> Result(Nil, StartError) {
  try _ =
    port
    |> tcp.listen([])
    |> result.map_error(fn(err) {
      case err {
        Closed -> ListenerClosed
        Timeout -> ListenerTimeout
      }
    })
    |> result.then(fn(socket) {
      socket
      |> with_pool
      |> acceptor.start_pool
      |> result.map_error(fn(err) {
        case err {
          actor.InitTimeout -> AcceptorTimeout
          actor.InitFailed(reason) -> AcceptorFailed(reason)
          actor.InitCrashed(reason) -> AcceptorCrashed(reason)
        }
      })
    })

  Ok(Nil)
}

pub fn echo_loop(
  msg: HandlerMessage,
  state: AcceptorState,
) -> actor.Next(AcceptorState) {
  case msg, state {
    ReceiveMessage(data), AcceptorState(socket: Some(sock), ..) -> {
      let _ = tcp.send(sock, bit_builder.from_bit_string(data))
      Nil
    }
    _, _ -> Nil
  }

  actor.Continue(state)
}
