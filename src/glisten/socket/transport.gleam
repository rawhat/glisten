import gleam/bytes_builder.{type BytesBuilder}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/dict.{type Dict}
import glisten/socket/options
import glisten/socket.{type ListenSocket, type Socket, type SocketReason}
import glisten/ssl
import glisten/tcp

type ControllingProcess =
  fn(Socket, Pid) -> Result(Nil, Atom)

type Listen =
  fn(Int, List(options.TcpOption)) -> Result(ListenSocket, SocketReason)

type AcceptTimeout =
  fn(ListenSocket, Int) -> Result(Socket, SocketReason)

type Accept =
  fn(ListenSocket) -> Result(Socket, SocketReason)

type ReceiveTimeout =
  fn(Socket, Int, Int) -> Result(BitArray, SocketReason)

type Receive =
  fn(Socket, Int) -> Result(BitArray, SocketReason)

type Send =
  fn(Socket, BytesBuilder) -> Result(Nil, SocketReason)

type SocketInfo =
  fn(Socket) -> Dict(Atom, Dynamic)

type Close =
  fn(Socket) -> Result(Nil, SocketReason)

type Shutdown =
  fn(Socket) -> Result(Nil, SocketReason)

type SetOpts =
  fn(Socket, List(options.TcpOption)) -> Result(Nil, Nil)

type Handshake =
  fn(Socket) -> Result(Socket, Nil)

type NegotiatedProtocol =
  fn(Socket) -> Result(String, String)

type PeerName =
  fn(Socket) -> Result(#(#(Int, Int, Int, Int), Int), Nil)

pub type Transport {
  Ssl(
    accept: Accept,
    accept_timeout: AcceptTimeout,
    close: Close,
    controlling_process: ControllingProcess,
    handshake: Handshake,
    listen: Listen,
    negotiated_protocol: NegotiatedProtocol,
    peername: PeerName,
    receive: Receive,
    receive_timeout: ReceiveTimeout,
    send: Send,
    set_opts: SetOpts,
    shutdown: Shutdown,
    socket_info: SocketInfo,
  )
  Tcp(
    accept: Accept,
    accept_timeout: AcceptTimeout,
    close: Close,
    controlling_process: ControllingProcess,
    handshake: Handshake,
    listen: Listen,
    negotiated_protocol: NegotiatedProtocol,
    peername: PeerName,
    receive: Receive,
    receive_timeout: ReceiveTimeout,
    send: Send,
    set_opts: SetOpts,
    shutdown: Shutdown,
    socket_info: SocketInfo,
  )
}

pub fn tcp() -> Transport {
  Tcp(
    accept: tcp.accept,
    accept_timeout: tcp.accept_timeout,
    close: tcp.close,
    controlling_process: tcp.controlling_process,
    handshake: tcp.handshake,
    listen: tcp.listen,
    negotiated_protocol: fn(_socket) {
      Error("Can't negotiate protocol on tcp")
    },
    peername: tcp.peername,
    receive: tcp.receive,
    receive_timeout: tcp.receive_timeout,
    send: tcp.send,
    set_opts: tcp.set_opts,
    shutdown: tcp.shutdown,
    socket_info: socket_info,
  )
}

pub fn ssl() -> Transport {
  Ssl(
    accept: ssl.accept,
    accept_timeout: ssl.accept_timeout,
    close: ssl.close,
    controlling_process: ssl.controlling_process,
    handshake: ssl.handshake,
    listen: ssl.listen,
    negotiated_protocol: ssl.negotiated_protocol,
    peername: ssl.peername,
    receive: ssl.receive,
    receive_timeout: ssl.receive_timeout,
    send: ssl.send,
    set_opts: ssl.set_opts,
    shutdown: ssl.shutdown,
    socket_info: socket_info,
  )
}

@external(erlang, "socket", "info")
pub fn socket_info(socket: Socket) -> Dict(a, b)
