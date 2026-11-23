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
  Listening(sock_name: socket.SockName, control: Control, socket: ListenSocket)
  AcceptingStopped(sock_name: socket.SockName, control: Control)
}

pub fn start(
  port: Int,
  transport: Transport,
  options: List(TcpOption),
  name: process.Name(Message),
  start_acceptors: fn(ListenSocket) -> Result(Nil, String),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(5000, fn(subject) {
    let control = process.new_subject()
    use socket <- result.try(
      transport.listen(transport, port, options)
      |> result.map_error(listener_start_failed),
    )
    use sock_name <- result.try(
      transport.sockname(transport, socket)
      |> result.map_error(listener_start_failed),
    )
    use _ <- result.try(start_acceptors(socket))
    Listening(sock_name:, control: Control(process.self(), control), socket:)
    |> actor.initialised
    |> actor.selecting(
      process.new_selector()
      |> process.select(subject)
      |> process.select(control),
    )
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(state, msg) {
    case msg {
      Info(caller) -> {
        process.send(caller, state)
        actor.continue(state)
      }
      StopAccepting(caller:) -> {
        case state {
          AcceptingStopped(..) -> {
            process.send(caller, Ok(Nil))
            actor.continue(state)
          }
          Listening(sock_name:, control:, socket:) -> {
            case transport.close_listener(transport, socket) {
              Ok(Nil) | Error(socket.Closed) -> {
                process.send(caller, Ok(Nil))
                actor.continue(AcceptingStopped(sock_name:, control:))
              }
              Error(reason) -> {
                process.send(caller, Error(reason))
                actor.continue(state)
              }
            }
          }
        }
      }
    }
  })
  |> actor.named(name)
  |> actor.start
}

fn listener_start_failed(reason: socket.SocketReason) -> String {
  let message =
    "Failed to start socket listener: " <> socket.reason_to_string(reason)
  logging.log(logging.Error, message)
  message
}
