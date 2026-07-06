import gleam/bytes_tree.{type BytesTree}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/result
import glisten/socket.{type ListenSocket, type Socket, type SocketReason}
import glisten/socket/options.{type TcpOption}

@external(erlang, "glisten_tcp_ffi", "controlling_process")
pub fn controlling_process(socket: Socket, pid: Pid) -> Result(Nil, Atom)

@external(erlang, "gen_tcp", "listen")
fn do_listen_tcp(
  port: Int,
  options: List(options.ErlangTcpOption),
) -> Result(ListenSocket, SocketReason)

@external(erlang, "gen_tcp", "accept")
pub fn accept_timeout(
  socket: ListenSocket,
  timeout: Int,
) -> Result(Socket, SocketReason)

@external(erlang, "gen_tcp", "accept")
pub fn accept(socket: ListenSocket) -> Result(Socket, SocketReason)

@external(erlang, "gen_tcp", "recv")
pub fn receive_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, SocketReason)

@external(erlang, "gen_tcp", "recv")
pub fn receive(socket: Socket, length: Int) -> Result(BitArray, SocketReason)

@external(erlang, "glisten_tcp_ffi", "unrecv")
fn do_unrecv(socket: Socket, data: BitArray) -> Result(Nil, SocketReason)

/// Peeks data from the given socket without consuming it, allowing the same data to be read in the future.
/// This may be used for probing data from a bytestream, without impacting any processing that expects to read data directly from a socket.
/// 
/// USE WITH CAUTION:
/// Callers expecting to repeatedly peek until a certain amount of data is buffered, *must not* call this function with a length value of 0.
/// The data returned from a receive with length=0 immediately after a peek should not be considered all data currently available to read.
/// 
/// This is a wrapper around successive receive and unrecv call. This reads some data, and then immediately re-queues it for the next receive.
/// This message cannot be appended with more data, and will likely behave unexpectedly with receive or peek calls intending to read all available data (parameter length value == 0).
/// That is, the next receive call (implicit if peeking) after a peek, will return the exact same data as the last peek even if more data is available to read.
pub fn peek_timeout(
  socket: Socket,
  length: Int,
  timeout: Int,
) -> Result(BitArray, SocketReason) {
  receive_timeout(socket, length, timeout)
  |> result.try(fn(msg) { do_unrecv(socket, msg) |> result.replace(msg) })
}

/// USE WITH CAUTION:
/// See the docs for peek_timeout
pub fn peek(socket: Socket, length: Int) -> Result(BitArray, SocketReason) {
  receive(socket, length)
  |> result.try(fn(msg) { do_unrecv(socket, msg) |> result.replace(msg) })
}

@external(erlang, "glisten_tcp_ffi", "send")
pub fn send(socket: Socket, packet: BytesTree) -> Result(Nil, SocketReason)

@external(erlang, "socket", "info")
pub fn socket_info(socket: Socket) -> Dict(a, b)

@external(erlang, "glisten_tcp_ffi", "close")
pub fn close(socket: a) -> Result(Nil, SocketReason)

@external(erlang, "glisten_tcp_ffi", "shutdown")
pub fn do_shutdown(socket: Socket, write: Atom) -> Result(Nil, SocketReason)

pub fn shutdown(socket: Socket) -> Result(Nil, SocketReason) {
  do_shutdown(socket, atom.create("write"))
}

@external(erlang, "glisten_tcp_ffi", "set_opts")
fn do_set_opts(
  socket: Socket,
  opts: List(options.ErlangTcpOption),
) -> Result(Nil, SocketReason)

/// Update the optons for a socket (mutates the socket)
pub fn set_opts(
  socket: Socket,
  opts: List(TcpOption),
) -> Result(Nil, SocketReason) {
  opts
  |> options.to_erl_options()
  |> do_set_opts(socket, _)
}

/// Start listening over TCP on a port with the given options
pub fn listen(
  port: Int,
  opts: List(TcpOption),
) -> Result(ListenSocket, SocketReason) {
  let is_unix =
    list.any(opts, fn(option) {
      case option {
        options.Ip(options.UnixPath(_)) -> True
        _ -> False
      }
    })

  let merged = case is_unix {
    True -> options.merge_with_unix_defaults(opts)
    False -> options.merge_with_tcp_defaults(opts)
  }

  options.to_erl_options(merged)
  |> do_listen_tcp(port, _)
}

pub fn handshake(socket: Socket) -> Result(Socket, Nil) {
  Ok(socket)
}

@external(erlang, "tcp", "negotiated_protocol")
pub fn negotiated_protocol(socket: Socket) -> a

@external(erlang, "glisten_tcp_ffi", "peername")
pub fn peername(
  socket: Socket,
) -> Result(#(options.IpAddress, Int), SocketReason)

@external(erlang, "inet", "getopts")
pub fn get_socket_opts(
  socket: Socket,
  opts: List(Atom),
) -> Result(List(#(Atom, Dynamic)), SocketReason)

@external(erlang, "glisten_tcp_ffi", "sockname")
pub fn sockname(socket: ListenSocket) -> Result(socket.SockName, SocketReason)
