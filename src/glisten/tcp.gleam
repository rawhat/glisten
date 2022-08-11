import gleam/bit_builder.{BitBuilder}
import gleam/dynamic.{Dynamic}
import gleam/erlang/atom.{Atom}
import gleam/erlang/process.{Abnormal, Pid, Subject}
import gleam/iterator
import gleam/function
import gleam/list
import gleam/map.{Map}
import gleam/option.{None, Option, Some}
import gleam/otp/actor
import gleam/otp/port.{Port}
import gleam/otp/supervisor.{add, worker}
import gleam/pair
import gleam/result
import glisten/logger

/// Mode for the socket.  Currently `list` is not supported
pub type SocketMode {
  Binary
}

/// Mapping to the {active, _} option
pub type ActiveState {
  Once
  Passive
  Count(Int)
  // This is dumb and annoying. I'd much prefer `True` or `Active`, but both
  // of those make this a lot more annoying to work with
  Active
}

/// Options for the TCP socket
pub type TcpOption {
  Backlog(Int)
  Nodelay(Bool)
  Linger(#(Bool, Int))
  SendTimeout(Int)
  SendTimeoutClose(Bool)
  Reuseaddr(Bool)
  ActiveMode(ActiveState)
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

external fn controlling_process(socket: Socket, pid: Pid) -> Result(Nil, Atom) =
  "tcp_ffi" "controlling_process"

external fn do_listen_tcp(
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

pub external fn receive_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitString, SocketReason) =
  "gen_tcp" "recv"

pub external fn receive(
  socket: Socket,
  length: Int,
) -> Result(BitString, SocketReason) =
  "gen_tcp" "recv"

pub external fn send(
  socket: Socket,
  packet: BitBuilder,
) -> Result(Nil, SocketReason) =
  "tcp_ffi" "send"

pub external fn socket_info(socket: Socket) -> Map(a, b) =
  "socket" "info"

pub external fn close(socket: a) -> Atom =
  "gen_tcp" "close"

pub external fn do_shutdown(socket: Socket, write: Atom) -> Nil =
  "gen_tcp" "shutdown"

pub fn shutdown(socket: Socket) {
  assert Ok(write) = atom.from_string("write")
  do_shutdown(socket, write)
}

external fn do_set_opts(socket: Socket, opts: List(Dynamic)) -> Result(Nil, Nil) =
  "tcp_ffi" "set_opts"

/// Update the optons for a socket (mutates the socket)
pub fn set_opts(socket: Socket, opts: List(TcpOption)) -> Result(Nil, Nil) {
  opts
  |> opts_to_map
  |> map.to_list
  |> list.map(dynamic.from)
  |> do_set_opts(socket, _)
}

fn opts_to_map(options: List(TcpOption)) -> Map(atom.Atom, Dynamic) {
  let opt_decoder = dynamic.tuple2(dynamic.dynamic, dynamic.dynamic)

  options
  |> list.map(fn(opt) {
    case opt {
      ActiveMode(Passive) ->
        dynamic.from(#(atom.create_from_string("active"), False))
      ActiveMode(Active) ->
        dynamic.from(#(atom.create_from_string("active"), True))
      ActiveMode(Count(n)) ->
        dynamic.from(#(atom.create_from_string("active"), n))
      ActiveMode(Once) ->
        dynamic.from(#(
          atom.create_from_string("active"),
          atom.create_from_string("once"),
        ))
      other -> dynamic.from(other)
    }
  })
  |> list.filter_map(opt_decoder)
  |> list.map(pair.map_first(_, dynamic.unsafe_coerce))
  |> map.from_list
}

fn merge_with_default_options(options: List(TcpOption)) -> List(TcpOption) {
  let overrides = opts_to_map(options)

  [
    Backlog(1024),
    Nodelay(True),
    Linger(#(True, 30)),
    SendTimeout(30_000),
    SendTimeoutClose(True),
    Reuseaddr(True),
    Mode(Binary),
    ActiveMode(Passive),
  ]
  |> opts_to_map
  |> map.merge(overrides)
  |> map.to_list
  |> list.map(dynamic.from)
  |> list.map(dynamic.unsafe_coerce)
}

/// Start listening over TCP on a port with the given options
pub fn listen(
  port: Int,
  options: List(TcpOption),
) -> Result(ListenSocket, SocketReason) {
  options
  |> merge_with_default_options
  |> do_listen_tcp(port, _)
}

pub type AcceptorMessage {
  AcceptConnection(ListenSocket)
}

pub type AcceptorError {
  AcceptError
  HandlerError
  ControlError
}

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

pub type AcceptorState {
  AcceptorState(sender: Subject(AcceptorMessage), socket: Option(Socket))
}

pub type LoopState(data) {
  LoopState(socket: Socket, sender: Subject(HandlerMessage), data: data)
}

pub type LoopFn(data) =
  fn(HandlerMessage, LoopState(data)) -> actor.Next(LoopState(data))

pub fn echo_loop(
  msg: HandlerMessage,
  state: AcceptorState,
) -> actor.Next(AcceptorState) {
  case msg, state {
    ReceiveMessage(data), AcceptorState(socket: Some(sock), ..) -> {
      let _ = send(sock, bit_builder.from_bit_string(data))
      Nil
    }
    _, _ -> Nil
  }

  actor.Continue(state)
}

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
pub fn start_handler(
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
          close(state.socket)
          let _ = case handler.on_close {
            Some(func) -> func(state.sender)
            _ -> Nil
          }
          actor.Stop(process.Normal)
        }
        Ready -> {
          assert Ok(_) = set_opts(state.socket, [ActiveMode(Once)])
          actor.Continue(state)
        }
        msg ->
          case handler.loop(msg, state) {
            actor.Continue(next_state) -> {
              assert Ok(Nil) = set_opts(state.socket, [ActiveMode(Once)])
              actor.Continue(next_state)
            }
            msg -> msg
          }
      }
    },
  ))
}

/// Worker process that handles `accept`ing connections and starts a new process
/// which receives the messages from the socket
pub fn start_acceptor(
  pool: AcceptorPool(data),
) -> Result(Subject(AcceptorMessage), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let subject = process.new_subject()
      let selector =
        process.new_selector()
        |> process.selecting(subject, function.identity)

      process.send(subject, AcceptConnection(pool.listener_socket))

      actor.Ready(AcceptorState(subject, None), selector)
    },
    // TODO:  rethink this value, probably...
    init_timeout: 1_000,
    loop: fn(msg, state) {
      let AcceptorState(sender, ..) = state
      case msg {
        AcceptConnection(listener) -> {
          let res = {
            try sock =
              accept(listener)
              |> result.replace_error(AcceptError)
            try start =
              Handler(
                sock,
                pool.initial_data,
                pool.handler,
                pool.on_init,
                pool.on_close,
              )
              |> start_handler
              |> result.replace_error(HandlerError)
            sock
            |> controlling_process(process.subject_owner(start))
            |> result.replace_error(ControlError)
            |> result.map(fn(_) { process.send(start, Ready) })
          }
          case res {
            Error(reason) -> {
              logger.error(#("Failed to accept/start handler", reason))
              actor.Stop(Abnormal("Failed to accept/start handler"))
            }
            _val -> {
              actor.send(sender, AcceptConnection(listener))
              actor.Continue(state)
            }
          }
        }
        msg -> {
          logger.error(#("Unknown message type", msg))
          actor.Stop(process.Abnormal("Unknown message type"))
        }
      }
    },
  ))
}

pub type AcceptorPool(data) {
  AcceptorPool(
    listener_socket: ListenSocket,
    handler: LoopFn(data),
    initial_data: data,
    pool_count: Int,
    on_init: Option(fn(Subject(HandlerMessage)) -> Nil),
    on_close: Option(fn(Subject(HandlerMessage)) -> Nil),
  )
}

/// Initialize acceptor pool where each handler has no state
pub fn acceptor_pool(
  handler: LoopFn(Nil),
) -> fn(ListenSocket) -> AcceptorPool(Nil) {
  fn(listener_socket) {
    AcceptorPool(
      listener_socket: listener_socket,
      handler: handler,
      initial_data: Nil,
      pool_count: 10,
      on_init: None,
      on_close: None,
    )
  }
}

/// Initialize an acceptor pool where each handler holds some state
pub fn acceptor_pool_with_data(
  handler: LoopFn(data),
  initial_data: data,
) -> fn(ListenSocket) -> AcceptorPool(data) {
  fn(listener_socket) {
    AcceptorPool(
      listener_socket: listener_socket,
      handler: handler,
      initial_data: initial_data,
      pool_count: 10,
      on_init: None,
      on_close: None,
    )
  }
}

/// Add an `on_init` handler to the acceptor pool
pub fn with_init(
  make_pool: fn(ListenSocket) -> AcceptorPool(data),
  func: fn(Subject(HandlerMessage)) -> Nil,
) -> fn(ListenSocket) -> AcceptorPool(data) {
  fn(socket) {
    let pool = make_pool(socket)
    AcceptorPool(..pool, on_init: Some(func))
  }
}

/// Add an `on_close` handler to the acceptor pool
pub fn with_close(
  make_pool: fn(ListenSocket) -> AcceptorPool(data),
  func: fn(Subject(HandlerMessage)) -> Nil,
) -> fn(ListenSocket) -> AcceptorPool(data) {
  fn(socket) {
    let pool = make_pool(socket)
    AcceptorPool(..pool, on_close: Some(func))
  }
}

/// Adjust the number of TCP acceptors in the pool
pub fn with_pool_size(
  make_pool: fn(ListenSocket) -> AcceptorPool(data),
  pool_count: Int,
) -> fn(ListenSocket) -> AcceptorPool(data) {
  fn(socket) {
    let pool = make_pool(socket)
    AcceptorPool(..pool, pool_count: pool_count)
  }
}

/// Starts a pool of acceptors of size `pool_count`.
///
/// Runs `loop_fn` on ever message received
pub fn start_acceptor_pool(
  pool: AcceptorPool(data),
) -> Result(Subject(supervisor.Message), actor.StartError) {
  supervisor.start_spec(supervisor.Spec(
    argument: Nil,
    // TODO:  i think these might need some tweaking
    max_frequency: 100,
    frequency_period: 1,
    init: fn(children) {
      iterator.range(from: 0, to: pool.pool_count)
      |> iterator.fold(
        children,
        fn(children, _index) {
          add(children, worker(fn(_arg) { start_acceptor(pool) }))
        },
      )
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
        case send(state.socket, data) {
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
