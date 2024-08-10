import gleam/bytes_builder.{type BytesBuilder}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervisor
import gleam/result
import glisten/internal/acceptor.{Pool}
import glisten/internal/handler
import glisten/internal/listener
import glisten/socket.{
  type Socket as InternalSocket, type SocketReason as InternalSocketReason,
}
import glisten/socket/options.{Certfile, Keyfile}
import glisten/ssl
import glisten/transport.{type Transport}

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

/// This is used to describe the connecting client's IP address.
pub type IpAddress {
  IpV4(Int, Int, Int, Int)
  IpV6(Int, Int, Int, Int, Int, Int, Int, Int)
}

pub type Socket =
  InternalSocket

pub type SocketReason =
  InternalSocketReason

/// This holds information about the server.  Returned by the `start_server` /
/// `start_ssl_server` methods, it will allow you to get access to an
/// OS-assigned port. Eventually, it will be used for graceful shutdown, and
/// potentially other information.
pub opaque type Server {
  Server(
    listener: Subject(listener.Message),
    supervisor: Subject(supervisor.Message),
    transport: Transport,
  )
}

pub type ConnectionInfo {
  ConnectionInfo(port: Int, ip_address: IpAddress)
}

/// Returns the user-provided port or the OS-assigned value if 0 was provided.
pub fn get_server_info(
  server: Server,
  timeout: Int,
) -> Result(ConnectionInfo, process.CallError(listener.State)) {
  process.try_call(server.listener, listener.Info, timeout)
  |> result.map(fn(state) {
    ConnectionInfo(state.port, convert_ip_address(state.ip_address))
  })
}

/// Gets the underlying supervisor `Subject` from the `Server`.
pub fn get_supervisor(server: Server) -> Subject(supervisor.Message) {
  server.supervisor
}

/// This type holds useful bits of data for the active connection.
pub type Connection(user_message) {
  Connection(
    socket: Socket,
    /// This provides a uniform interface for both TCP and SSL methods.
    transport: Transport,
    subject: Subject(handler.Message(user_message)),
  )
}

@internal
pub fn convert_ip_address(ip: transport.IpAddress) -> IpAddress {
  case ip {
    transport.IpV4(a, b, c, d) -> IpV4(a, b, c, d)
    transport.IpV6(a, b, c, d, e, f, g, h) -> IpV6(a, b, c, d, e, f, g, h)
  }
}

/// Tries to read the IP address and port of a connected client.  It will
/// return valid IPv4 or IPv6 addresses, attempting to return the most relevant
/// one for the client.
pub fn get_client_info(
  conn: Connection(user_message),
) -> Result(ConnectionInfo, Nil) {
  transport.peername(conn.transport, conn.socket)
  |> result.map(fn(pair) { ConnectionInfo(pair.1, convert_ip_address(pair.0)) })
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
    http2_support: Bool,
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
    let conn = Connection(conn.socket, conn.transport, conn.sender)
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
  Handler(
    on_init: on_init,
    loop: loop,
    on_close: None,
    pool_size: 10,
    http2_support: False,
  )
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

/// Sets the ALPN supported protocols to include HTTP/2.  It's currently being
/// exposed only for `mist` to provide this support.  For a TCP library, you
/// definitely do not need it.
pub fn with_http2(
  handler: Handler(user_message, data),
) -> Handler(user_message, data) {
  Handler(..handler, http2_support: True)
}

/// Start the TCP server with the given handler on the provided port
pub fn serve(
  handler: Handler(user_message, data),
  port: Int,
) -> Result(Subject(supervisor.Message), StartError) {
  start_server(handler, port)
  |> result.map(get_supervisor)
}

/// Start the SSL server with the given handler on the provided port.  The key
/// and cert files must be provided, valid, and readable by the current user.
pub fn serve_ssl(
  handler: Handler(user_message, data),
  port port: Int,
  certfile certfile: String,
  keyfile keyfile: String,
) -> Result(Subject(supervisor.Message), StartError) {
  start_ssl_server(handler, port, certfile, keyfile)
  |> result.map(get_supervisor)
}

/// Starts a TCP server and returns the `Server` construct.  This is useful if
/// you need access to the port. In the future, it will also allow graceful
/// shutdown. There may also be other metadata attached to this return value.
pub fn start_server(
  handler: Handler(user_message, data),
  port: Int,
) -> Result(Server, StartError) {
  let return = process.new_subject()

  let selector =
    process.new_selector()
    |> process.selecting(return, fn(subj) { subj })

  Pool(
    handler: convert_loop(handler.loop),
    pool_count: handler.pool_size,
    on_init: convert_on_init(handler.on_init),
    on_close: handler.on_close,
    transport: transport.Tcp,
  )
  |> acceptor.start_pool(transport.Tcp, port, [], return)
  |> result.map_error(fn(err) {
    case err {
      actor.InitTimeout -> AcceptorTimeout
      actor.InitFailed(reason) -> AcceptorFailed(reason)
      actor.InitCrashed(reason) -> AcceptorCrashed(reason)
    }
  })
  |> result.then(fn(pool) {
    process.select(selector, 1500)
    |> result.map(fn(listener) {
      Server(listener: listener, supervisor: pool, transport: transport.Tcp)
    })
    |> result.replace_error(AcceptorTimeout)
  })
}

/// Starts an SSL server and returns the `Server` construct.  This is useful if
/// you need access to the port. In the future, it will also allow graceful
/// shutdown. There may also be other metadata attached to this return value.
pub fn start_ssl_server(
  handler: Handler(user_message, data),
  port port: Int,
  certfile certfile: String,
  keyfile keyfile: String,
) -> Result(Server, StartError) {
  let assert Ok(_nil) = ssl.start()
  let ssl_options = [Certfile(certfile), Keyfile(keyfile)]
  let protocol_options = case handler.http2_support {
    True -> [options.AlpnPreferredProtocols(["h2", "http/1.1"])]
    False -> [options.AlpnPreferredProtocols(["http/1.1"])]
  }

  let return = process.new_subject()

  let selector =
    process.new_selector()
    |> process.selecting(return, fn(subj) { subj })

  Pool(
    handler: convert_loop(handler.loop),
    pool_count: handler.pool_size,
    on_init: convert_on_init(handler.on_init),
    on_close: handler.on_close,
    transport: transport.Ssl,
  )
  |> acceptor.start_pool(
    transport.Ssl,
    port,
    list.concat([ssl_options, protocol_options]),
    return,
  )
  |> result.map_error(fn(err) {
    case err {
      actor.InitTimeout -> AcceptorTimeout
      actor.InitFailed(reason) -> AcceptorFailed(reason)
      actor.InitCrashed(reason) -> AcceptorCrashed(reason)
    }
  })
  |> result.then(fn(pool) {
    process.select(selector, 1500)
    |> result.map(fn(listener) {
      Server(listener: listener, supervisor: pool, transport: transport.Tcp)
    })
    |> result.replace_error(AcceptorTimeout)
  })
}
