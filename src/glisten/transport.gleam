import gleam/bytes_builder.{type BytesBuilder}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Decoder, type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/result
import glisten/socket.{type ListenSocket, type Socket, type SocketReason}
import glisten/socket/options
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

fn decode_ipv4() -> Decoder(options.IpAddress) {
  dynamic.decode4(
    options.IpV4,
    dynamic.element(0, dynamic.int),
    dynamic.element(1, dynamic.int),
    dynamic.element(2, dynamic.int),
    dynamic.element(3, dynamic.int),
  )
}

fn decode_ipv6() -> Decoder(options.IpAddress) {
  fn(dyn) {
    dynamic.decode8(
      options.IpV6,
      dynamic.element(0, dynamic.int),
      dynamic.element(1, dynamic.int),
      dynamic.element(2, dynamic.int),
      dynamic.element(3, dynamic.int),
      dynamic.element(4, dynamic.int),
      dynamic.element(5, dynamic.int),
      dynamic.element(6, dynamic.int),
      dynamic.element(7, dynamic.int),
    )(dyn)
    |> result.then(fn(ip) {
      case ip {
        options.IpV6(0, 0, 0, 0, 0, 65_535, a, b) -> {
          decode_ipv4()(convert_address(#(0, 0, 0, 0, 0, 65_535, a, b)))
        }
        _ -> Ok(ip)
      }
    })
  }
}

pub fn decode_ip() -> Decoder(options.IpAddress) {
  dynamic.any([decode_ipv6(), decode_ipv4()])
}

pub fn peername(
  transport: Transport,
  socket: Socket,
) -> Result(#(options.IpAddress, Int), Nil) {
  case transport {
    Tcp -> tcp.peername(socket)
    Ssl -> ssl.peername(socket)
  }
  |> result.then(fn(pair) {
    let #(ip_address, port) = pair
    decode_ip()(ip_address)
    |> result.map(fn(ip) { #(ip, port) })
    |> result.nil_error
  })
}

@external(erlang, "inet", "ipv4_mapped_ipv6_address")
fn convert_address(address: address) -> Dynamic

@external(erlang, "socket", "info")
pub fn socket_info(socket: Socket) -> Dict(Atom, Dynamic)

pub fn get_socket_opts(
  transport: Transport,
  socket: Socket,
  opts: List(Atom),
) -> Result(List(#(Atom, Dynamic)), Nil) {
  case transport {
    Tcp -> tcp.get_socket_opts(socket, opts)
    Ssl -> ssl.get_socket_opts(socket, opts)
  }
}

pub fn set_buffer_size(transport: Transport, socket: Socket) -> Result(Nil, Nil) {
  get_socket_opts(transport, socket, [atom.create_from_string("recbuf")])
  |> result.then(fn(p) {
    case p {
      [#(_buffer, value)] -> result.nil_error(dynamic.int(value))
      _ -> Error(Nil)
    }
  })
  |> result.then(fn(value) {
    set_opts(transport, socket, [options.Buffer(value)])
  })
}

pub fn sockname(
  transport: Transport,
  socket: ListenSocket,
) -> Result(#(options.IpAddress, Int), SocketReason) {
  case transport {
    Tcp -> tcp.sockname(socket)
    Ssl -> ssl.sockname(socket)
  }
  |> result.then(fn(pair) {
    let #(maybe_ip, port) = pair
    decode_ip()(maybe_ip)
    |> result.map(fn(ip) { #(ip, port) })
    |> result.replace_error(socket.Badarg)
  })
}
