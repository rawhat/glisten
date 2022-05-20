import gleam/dynamic.{Dynamic}
import gleam/otp/actor
import gleam/otp/process
import gleam/result
import glisten/tcp.{Closed, Timeout, start_acceptor_pool}

/// Reasons that `serve` might fail
pub type StartError {
  ListenerClosed
  ListenerTimeout
  AcceptorTimeout
  AcceptorFailed(process.ExitReason)
  AcceptorCrashed(Dynamic)
}

/// Sets up a TCP server listener at the provided port. Also takes the
/// HttpHandler, which holds the handler function.  There are currently two
/// options for ease of use: `http.handler` and `ws.handler`.
pub fn serve(
  port: Int,
  handler: tcp.LoopFn(state),
  initial_state: state,
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
      |> start_acceptor_pool(handler, initial_state, 10)
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
