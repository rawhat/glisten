import gleam/dynamic.{Dynamic}
import gleam/erlang/atom
import gleam/io
import gleam/iterator.{Iterator, Next}
import gleam/list
import gleam/map.{Map}
import gleam/option.{None, Option, Some}
import gleam/otp/actor
import gleam/otp/port.{Port}
import gleam/otp/process.{Pid, Receiver, Sender}
import gleam/otp/supervisor.{add, worker}
import gleam/pair

pub type SocketMode {
  Binary
}

pub type TcpOption {
  Active(Bool)
  Backlog(Int)
  Nodelay(Bool)
  Linger(#(Bool, Int))
  SendTimeout(Int)
  SendTimeoutClose(Bool)
  Reuseaddr(Bool)
  Mode(SocketMode)
}

pub type SocketReason {
  Closed
  Timeout
}

pub opaque type ListenSocket {
  ListenSocket
}

pub opaque type Socket {
  Socket
}

external fn controlling_process(
  socket: Socket,
  pid: Pid,
) -> Result(Nil, SocketReason) =
  "gen_tcp" "controlling_process"

pub external fn do_listen_tcp(
  port: Int,
  options: List(TcpOption),
) -> Result(ListenSocket, SocketReason) =
  "gen_tcp" "listen"

pub external fn accept_timeout(
  socket: ListenSocket,
  timeout: Int,
) -> Result(Socket, SocketReason) =
  "gen_tcp" "accept"

pub external fn accept(socket: ListenSocket) -> Result(Socket, SocketReason) =
  "gen_tcp" "accept"

external fn do_receive_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitString, SocketReason) =
  "gen_tcp" "recv"

pub external fn do_receive(
  socket: Socket,
  length: Int,
) -> Result(BitString, SocketReason) =
  "gen_tcp" "recv"

pub external fn send(
  socket: Socket,
  packet: BitString,
) -> Result(Nil, SocketReason) =
  "gen_tcp" "send"

fn opts_to_map(options: List(TcpOption)) -> Map(atom.Atom, Dynamic) {
  let opt_decoder = dynamic.tuple2(dynamic.dynamic, dynamic.dynamic)

  options
  |> list.map(dynamic.from)
  |> list.filter_map(opt_decoder)
  |> list.map(pair.map_first(_, dynamic.unsafe_coerce))
  |> map.from_list
}

pub fn merge_with_default_options(options: List(TcpOption)) -> List(TcpOption) {
  let overrides = opts_to_map(options)

  [
    Backlog(1024),
    Nodelay(True),
    Linger(#(True, 30)),
    SendTimeout(30_000),
    SendTimeoutClose(True),
    Reuseaddr(True),
    Mode(Binary),
  ]
  // Active(False),
  |> opts_to_map
  |> map.merge(overrides)
  |> map.to_list
  |> list.map(dynamic.from)
  |> list.map(dynamic.unsafe_coerce)
}

pub fn listen_tcp(
  port: Int,
  options: List(TcpOption),
) -> Result(ListenSocket, SocketReason) {
  options
  |> merge_with_default_options
  |> do_listen_tcp(port, _)
}

pub fn receive(socket: Socket) -> Result(BitString, SocketReason) {
  do_receive(socket, 0)
}

// type RawMessage {
//   Tcp(socket: Port, data: BitString)
// }
pub type Acceptor {
  AcceptConnection(ListenSocket)
  SendMessage(BitString)
  ReceiveMessage(BitString)
  Tcp(socket: Port, data: BitString)
}

pub type Channel =
  #(Socket, Receiver(Acceptor))

pub type AcceptorState {
  AcceptorState(sender: Sender(Acceptor), socket: Option(Socket))
}

pub type LoopFn =
  fn(Acceptor, AcceptorState) -> actor.Next(AcceptorState)

pub fn echo_loop(
  msg: Acceptor,
  state: AcceptorState,
) -> actor.Next(AcceptorState) {
  io.debug(#("got a message", msg, "with a sender", state))

  case msg, state {
    ReceiveMessage(data), AcceptorState(socket: Some(sock), ..) -> {
      let _ = send(sock, data)
      Nil
    }
    _, _ -> Nil
  }

  actor.Continue(state)
}

// message type should be like
//   SendMessage
//   ReceiveMessage ?
pub fn start_acceptor(
  socket: ListenSocket,
  loop_fn: LoopFn,
) -> Result(Sender(Acceptor), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let #(sender, actor_receiver) = process.new_channel()

      let socket_receiver =
        process.bare_message_receiver()
        |> process.map_receiver(fn(msg) {
          case dynamic.unsafe_coerce(msg) {
            Tcp(_sock, data) -> ReceiveMessage(data)
            message -> message
          }
        })

      process.send(sender, AcceptConnection(socket))

      let receiver = process.merge_receiver(actor_receiver, socket_receiver)

      actor.Ready(AcceptorState(sender, None), Some(receiver))
    },
    init_timeout: 30_000_000,
    loop: fn(msg, state) {
      io.println("in loop with a message")
      io.debug(msg)
      let AcceptorState(sender, sock) = state
      case msg {
        AcceptConnection(listener) -> {
          io.println("attempting to accept")
          assert Ok(sock) = accept(listener)
          io.println("i have accepted!")
          let _res = controlling_process(sock, process.pid(sender))
          actor.Continue(AcceptorState(..state, socket: Some(sock)))
        }
        SendMessage(msg) -> {
          assert Some(socket) = sock
          io.println("sending a message!")
          let _ = send(socket, msg)
          actor.Continue(state)
        }
        msg -> loop_fn(msg, state)
      }
    },
  ))
}

pub fn receive_timeout(
  socket: Socket,
  timeout: Int,
) -> Result(BitString, SocketReason) {
  do_receive_timeout(socket, 0, timeout)
}

pub fn receiver_to_iterator(receiver: Receiver(a)) -> Iterator(a) {
  iterator.unfold(
    from: receiver,
    with: fn(recv) {
      recv
      |> process.receive_forever
      |> Next(accumulator: recv)
    },
  )
}

pub fn start_acceptor_pool(
  listener_socket: ListenSocket,
  handler: LoopFn,
  pool_count: Int,
) -> Result(Nil, Nil) {
  let _ = supervisor.start_spec(supervisor.Spec(
    argument: Nil,
    max_frequency: 5,
    frequency_period: 1,
    init: fn(children) {
      iterator.range(from: 0, to: pool_count)
      |> iterator.fold(
        children,
        fn(children, _index) {
          add(
            children,
            worker(fn(_arg) { start_acceptor(listener_socket, handler) }),
          )
        },
      )
    },
  ))

  Ok(Nil)
}
