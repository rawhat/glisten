import gleam/dynamic.{Dynamic}
import gleam/otp/actor
import gleam/otp/process
import gleam/result
import glisten/tcp.{
  AcceptorPool, Closed, ListenSocket, Timeout, start_acceptor_pool,
}

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
  with_pool: fn(ListenSocket) -> AcceptorPool(data),
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
      |> start_acceptor_pool
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
