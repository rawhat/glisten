import gleam/bytes_builder.{type BytesBuilder}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/dict.{type Dict}
import glisten/socket/options
import glisten/socket.{type ListenSocket, type Socket, type SocketReason}
import glisten/ssl
import glisten/tcp

pub type Transport {
  Tcp
  Ssl
}

pub fn controlling_process(
  transport: Transport,
  socket: Socket,
  pid: Pid,
) -> Result(Nil, Atom) {
  case transport {
    Tcp -> tcp.controlling_process(socket, pid)
    Ssl -> ssl.controlling_process(socket, pid)
  }
}

pub fn listen(
  transport: Transport,
  port: Int,
  opts: List(options.TcpOption),
) -> Result(ListenSocket, SocketReason) {
  case transport {
    Tcp -> tcp.listen(port, opts)
    Ssl -> ssl.listen(port, opts)
  }
}

pub fn accept_timeout(
  transport: Transport,
  socket: ListenSocket,
  timeout: Int,
) -> Result(Socket, SocketReason) {
  case transport {
    Tcp -> tcp.accept_timeout(socket, timeout)
    Ssl -> ssl.accept_timeout(socket, timeout)
  }
}

pub fn accept(
  transport: Transport,
  socket: ListenSocket,
) -> Result(Socket, SocketReason) {
  case transport {
    Tcp -> tcp.accept(socket)
    Ssl -> ssl.accept(socket)
  }
}

pub fn handshake(transport: Transport, socket: Socket) -> Result(Socket, Nil) {
  case transport {
    Tcp -> tcp.handshake(socket)
    Ssl -> ssl.handshake(socket)
  }
}

pub fn receive_timeout(
  transport: Transport,
  socket: Socket,
  amount: Int,
  timeout: Int,
) -> Result(BitArray, SocketReason) {
  case transport {
    Tcp -> tcp.receive_timeout(socket, amount, timeout)
    Ssl -> ssl.receive_timeout(socket, amount, timeout)
  }
}

pub fn receive(
  transport: Transport,
  socket: Socket,
  amount: Int,
) -> Result(BitArray, SocketReason) {
  case transport {
    Tcp -> tcp.receive(socket, amount)
    Ssl -> ssl.receive(socket, amount)
  }
}

pub fn send(
  transport: Transport,
  socket: Socket,
  data: BytesBuilder,
) -> Result(Nil, SocketReason) {
  case transport {
    Tcp -> tcp.send(socket, data)
    Ssl -> ssl.send(socket, data)
  }
}

pub fn close(transport: Transport, socket: Socket) -> Result(Nil, SocketReason) {
  case transport {
    Tcp -> tcp.close(socket)
    Ssl -> ssl.close(socket)
  }
}

pub fn shutdown(
  transport: Transport,
  socket: Socket,
) -> Result(Nil, SocketReason) {
  case transport {
    Tcp -> tcp.shutdown(socket)
    Ssl -> ssl.shutdown(socket)
  }
}

pub fn set_opts(
  transport: Transport,
  socket: Socket,
  opts: List(options.TcpOption),
) -> Result(Nil, Nil) {
  case transport {
    Tcp -> tcp.set_opts(socket, opts)
    Ssl -> ssl.set_opts(socket, opts)
  }
}

pub fn negotiated_protocol(
  transport: Transport,
  socket: Socket,
) -> Result(String, String) {
  case transport {
    Tcp -> Error("Can't negotiate protocol on tcp")
    Ssl -> ssl.negotiated_protocol(socket)
  }
}

pub fn peername(
  transport: Transport,
  socket: Socket,
) -> Result(#(#(Int, Int, Int, Int), Int), Nil) {
  case transport {
    Tcp -> tcp.peername(socket)
    Ssl -> ssl.peername(socket)
  }
}

@external(erlang, "socket", "info")
pub fn socket_info(socket: Socket) -> Dict(Atom, Dynamic)
