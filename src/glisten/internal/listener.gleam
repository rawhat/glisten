import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result
import glisten/socket.{type ListenSocket}
import glisten/socket/options.{type TcpOption}
import glisten/transport.{type Transport}
import logging

pub type Message {
  Info(caller: Subject(State))
  StopAccepting(caller: Subject(Result(Nil, socket.SocketReason)))
}

/// The listening socket's owner and its direct message subject.
pub type Control {
  Control(pid: process.Pid, subject: Subject(Message))
}

pub type State {
  State(
    listen_socket: ListenSocket,
    sock_name: socket.SockName,
    control: Control,
  )
}

pub fn start(
  port: Int,
  transport: Transport,
  options: List(TcpOption),
  name: process.Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(subject) {
    let control = process.new_subject()
    transport.listen(transport, port, options)
    |> result.try(fn(socket) {
      transport.sockname(transport, socket)
      |> result.map(fn(sock_name) {
        State(
          listen_socket: socket,
          sock_name:,
          control: Control(pid: process.self(), subject: control),
        )
      })
    })
    |> result.map(fn(state) {
      state
      |> actor.initialised
      |> actor.selecting(
        process.new_selector()
        |> process.select(subject)
        |> process.select(control),
      )
      |> actor.returning(subject)
    })
    |> result.map_error(fn(err) {
      let error_string =
        "Failed to start socket listener: " <> socket.reason_to_string(err)
      logging.log(logging.Error, error_string)
      error_string
    })
  })
  |> actor.on_message(fn(state, msg) {
    case msg {
      Info(caller) -> {
        process.send(caller, state)
        actor.continue(state)
      }
      StopAccepting(caller:) -> {
        case transport.close_listener(transport, state.listen_socket) {
          Ok(Nil) | Error(socket.Closed) -> process.send(caller, Ok(Nil))
          Error(reason) -> process.send(caller, Error(reason))
        }
        actor.continue(state)
      }
    }
  })
  |> actor.named(name)
  |> actor.start
}
