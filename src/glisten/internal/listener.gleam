import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten/socket.{type ListenSocket}
import glisten/socket/options.{type TcpOption}
import glisten/transport.{type Transport}

pub type Message {
  Info(caller: Subject(State))
}

pub type State {
  // TODO:  Add IP address?
  State(listen_socket: ListenSocket, port: Int)
}

pub fn start(
  port: Int,
  transport: Transport,
  options: List(TcpOption),
) -> Result(Subject(Message), actor.StartError) {
  actor.start_spec(
    actor.Spec(
      init: fn() {
        transport.listen(transport, port, options)
        |> result.then(fn(socket) {
          transport.port(transport, socket)
          |> result.map(fn(port) { State(listen_socket: socket, port: port) })
        })
        |> result.map(fn(state) { actor.Ready(state, process.new_selector()) })
        |> result.map_error(fn(err) {
          actor.Failed(
            "Failed to start socket listener: " <> string.inspect(err),
          )
        })
        |> result.unwrap_both
      },
      init_timeout: 5000,
      loop: fn(msg, state) {
        case msg {
          Info(caller) -> {
            process.send(caller, state)
            actor.continue(state)
          }
        }
      },
    ),
  )
}
