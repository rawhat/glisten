import gleam/bytes_builder.{type BytesBuilder}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/result
import glisten/internal/acceptor.{Pool}
import glisten/internal/handler.{type ClientIp as InternalClientIp}
import glisten/socket.{
  type Socket as InternalSocket, type SocketReason as InternalSocketReason,
  Closed, Timeout,
}
import glisten/socket/options.{Certfile, Keyfile}
import glisten/transport.{type Transport}
import glisten/tcp
import glisten/ssl
import gleam/otp/actor
import gleam/otp/supervisor

/// Reasons that `serve` might fail
pub type StartError {
  ListenerClosed
  ListenerTimeout
  AcceptorTimeout
  AcceptorFailed(process.ExitReason)
  AcceptorCrashed(Dynamic)
  SystemError(SocketReason)
}

/// Your provided loop function with receive these message types as the
/// first argument.
pub type Message(user_message) {
  /// These are messages received from the socket
  Packet(BitArray)
  /// These are any messages received from the selector returned from `on_init`
  User(user_message)
}

pub type ClientIp =
  InternalClientIp

pub type Socket =
  InternalSocket

pub type SocketReason =
  InternalSocketReason

/// This type holds useful bits of data for the active connection.
pub type Connection(user_message) {
  Connection(
    /// This will be optionally a tuple for the IPv4 of the other end of the
    /// socket
    client_ip: ClientIp,
    socket: Socket,
    /// This provides a uniform interface for both TCP and SSL methods.
    transport: Transport,
    subject: Subject(handler.Message(user_message)),
  )
}

/// Sends a BytesBuilder message over the socket using the active transport
pub fn send(
  conn: Connection(user_message),
  msg: BytesBuilder,
) -> Result(Nil, SocketReason) {
  transport.send(conn.transport, conn.socket, msg)
}

/// This is the shape of the function you need to provide for the `handler`
/// argument to `serve(_ssl)`.
pub type Loop(user_message, data) =
  fn(Message(user_message), data, Connection(user_message)) ->
    actor.Next(Message(user_message), data)

pub opaque type Handler(user_message, data) {
  Handler(
    on_init: fn(Connection(user_message)) ->
      #(data, Option(Selector(user_message))),
    loop: Loop(user_message, data),
    on_close: Option(fn(data) -> Nil),
    pool_size: Int,
  )
}

fn map_user_selector(
  selector: Selector(Message(user_message)),
) -> Selector(handler.LoopMessage(user_message)) {
  process.map_selector(selector, fn(value) {
    case value {
      Packet(msg) -> handler.Packet(msg)
      User(msg) -> handler.Custom(msg)
    }
  })
}

fn convert_loop(
  loop: Loop(user_message, data),
) -> handler.Loop(user_message, data) {
  fn(msg, data, conn: handler.Connection(user_message)) {
    let conn =
      Connection(conn.client_ip, conn.socket, conn.transport, conn.sender)
    case msg {
      handler.Packet(msg) -> {
        case loop(Packet(msg), data, conn) {
          actor.Continue(data, selector) ->
            actor.Continue(data, option.map(selector, map_user_selector))
          actor.Stop(reason) -> actor.Stop(reason)
        }
      }
      handler.Custom(msg) -> {
        case loop(User(msg), data, conn) {
          actor.Continue(data, selector) ->
            actor.Continue(data, option.map(selector, map_user_selector))
          actor.Stop(reason) -> actor.Stop(reason)
        }
      }
    }
  }
}

fn convert_on_init(
  on_init: fn(Connection(user_message)) ->
    #(state, Option(Selector(user_message))),
) -> fn(handler.Connection(user_message)) ->
  #(state, Option(Selector(user_message))) {
  fn(conn: handler.Connection(user_message)) {
    let connection =
      Connection(
        client_ip: conn.client_ip,
        subject: conn.sender,
        socket: conn.socket,
        transport: conn.transport,
      )
    on_init(connection)
  }
}

/// Create a new handler for each connection.  The required arguments mirror the
/// `actor.start` API from `gleam_otp`.  The default pool is 10 accceptor
/// processes.
pub fn handler(
  on_init: fn(Connection(user_message)) ->
    #(data, Option(Selector(user_message))),
  loop: Loop(user_message, data),
) -> Handler(user_message, data) {
  Handler(on_init: on_init, loop: loop, on_close: None, pool_size: 10)
}

/// Adds a function to the handler to be called when the connection is closed.
pub fn with_close(
  handler: Handler(user_message, data),
  on_close: fn(data) -> Nil,
) -> Handler(user_message, data) {
  Handler(..handler, on_close: Some(on_close))
}

/// Modify the size of the acceptor pool
pub fn with_pool_size(
  handler: Handler(user_message, data),
  size: Int,
) -> Handler(user_message, data) {
  Handler(..handler, pool_size: size)
}

/// Start the TCP server with the given handler on the provided port
pub fn serve(
  handler: Handler(user_message, data),
  port: Int,
) -> Result(Subject(supervisor.Message), StartError) {
  port
  |> tcp.listen([])
  |> result.map_error(fn(err) {
    case err {
      Closed -> ListenerClosed
      Timeout -> ListenerTimeout
      err -> SystemError(err)
    }
  })
  |> result.then(fn(socket) {
    Pool(
      listener_socket: socket,
      handler: convert_loop(handler.loop),
      pool_count: handler.pool_size,
      on_init: convert_on_init(handler.on_init),
      on_close: handler.on_close,
      transport: transport.Tcp,
    )
    |> acceptor.start_pool
    |> result.map_error(fn(err) {
      case err {
        actor.InitTimeout -> AcceptorTimeout
        actor.InitFailed(reason) -> AcceptorFailed(reason)
        actor.InitCrashed(reason) -> AcceptorCrashed(reason)
      }
    })
  })
}

/// Start the SSL server with the given handler on the provided port.  The key
/// and cert files must be provided, valid, and readable by the current user.
pub fn serve_ssl(
  handler: Handler(user_message, data),
  port port: Int,
  certfile certfile: String,
  keyfile keyfile: String,
) -> Result(Subject(supervisor.Message), StartError) {
  let assert Ok(_nil) = ssl.start()
  port
  |> ssl.listen([Certfile(certfile), Keyfile(keyfile)])
  |> result.map_error(fn(err) {
    case err {
      Closed -> ListenerClosed
      Timeout -> ListenerTimeout
      err -> SystemError(err)
    }
  })
  |> result.then(fn(socket) {
    Pool(
      listener_socket: socket,
      handler: convert_loop(handler.loop),
      pool_count: handler.pool_size,
      on_init: convert_on_init(handler.on_init),
      on_close: handler.on_close,
      transport: transport.Ssl,
    )
    |> acceptor.start_pool
    |> result.map_error(fn(err) {
      case err {
        actor.InitTimeout -> AcceptorTimeout
        actor.InitFailed(reason) -> AcceptorFailed(reason)
        actor.InitCrashed(reason) -> AcceptorCrashed(reason)
      }
    })
  })
}
