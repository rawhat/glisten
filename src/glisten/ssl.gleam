import gleam/bytes_builder.{type BytesBuilder}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/list
import glisten/socket.{type ListenSocket, type Socket, type SocketReason}
import glisten/socket/options

@external(erlang, "glisten_ssl_ffi", "controlling_process")
pub fn controlling_process(socket: Socket, pid: Pid) -> Result(Nil, Atom)

@external(erlang, "ssl", "listen")
fn do_listen(
  port: Int,
  options: List(options.TcpOption),
) -> Result(ListenSocket, SocketReason)

@external(erlang, "ssl", "transport_accept")
pub fn accept_timeout(
  socket: ListenSocket,
  timeout: Int,
) -> Result(Socket, SocketReason)

@external(erlang, "ssl", "transport_accept")
pub fn accept(socket: ListenSocket) -> Result(Socket, SocketReason)

@external(erlang, "ssl", "recv")
pub fn receive_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, SocketReason)

@external(erlang, "ssl", "recv")
pub fn receive(socket: Socket, length: Int) -> Result(BitArray, SocketReason)

@external(erlang, "glisten_ssl_ffi", "send")
pub fn send(socket: Socket, packet: BytesBuilder) -> Result(Nil, SocketReason)

@external(erlang, "glisten_ssl_ffi", "close")
pub fn close(socket: Socket) -> Result(Nil, SocketReason)

@external(erlang, "glisten_ssl_ffi", "shutdown")
pub fn do_shutdown(socket: Socket, write: Atom) -> Result(Nil, SocketReason)

pub fn shutdown(socket: Socket) -> Result(Nil, SocketReason) {
  let assert Ok(write) = atom.from_string("write")
  do_shutdown(socket, write)
}

@external(erlang, "glisten_ssl_ffi", "set_opts")
fn do_set_opts(socket: Socket, opts: List(Dynamic)) -> Result(Nil, Nil)

/// Update the optons for a socket (mutates the socket)
pub fn set_opts(
  socket: Socket,
  opts: List(options.TcpOption),
) -> Result(Nil, Nil) {
  opts
  |> options.to_dict
  |> dict.to_list
  |> list.map(dynamic.from)
  |> do_set_opts(socket, _)
}

@external(erlang, "ssl", "handshake")
pub fn handshake(socket: Socket) -> Result(Socket, Nil)

/// Start listening over SSL on a port with the given options
pub fn listen(
  port: Int,
  options: List(options.TcpOption),
) -> Result(ListenSocket, SocketReason) {
  options
  |> options.merge_with_defaults
  |> do_listen(port, _)
}

@external(erlang, "glisten_ssl_ffi", "negotiated_protocol")
pub fn negotiated_protocol(socket: Socket) -> Result(String, String)

@external(erlang, "ssl", "peername")
pub fn peername(socket: Socket) -> Result(#(Dynamic, Int), Nil)

@external(erlang, "ssl", "sockname")
pub fn sockname(socket: ListenSocket) -> Result(#(Dynamic, Int), SocketReason)

@external(erlang, "glisten_ssl_ffi", "start_ssl")
pub fn start() -> Result(Nil, Dynamic)

@external(erlang, "ssl", "getopts")
pub fn get_socket_opts(
  socket: Socket,
  opts: List(Atom),
) -> Result(List(#(Atom, Dynamic)), Nil)
