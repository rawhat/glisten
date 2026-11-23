import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import glisten/socket.{type Socket, type SocketReason}

@external(erlang, "gen_tcp", "connect")
fn tcp_connect(
  host: Charlist,
  port: Int,
  options: List(Dynamic),
) -> Result(Socket, Nil)

@external(erlang, "gen_tcp", "connect")
fn tcp_connect_timeout(
  host: Charlist,
  port: Int,
  options: List(Dynamic),
  timeout: Int,
) -> Result(Socket, SocketReason)

@external(erlang, "gleam@function", "identity")
fn from(value: a) -> Dynamic

pub fn connect(port: Int) -> Socket {
  let assert Ok(client) =
    tcp_connect(charlist.from_string("localhost"), port, [
      from(atom.create("binary")),
    ])
  client
}

pub fn connect_passive(port: Int) -> Result(Socket, SocketReason) {
  tcp_connect_timeout(
    charlist.from_string("127.0.0.1"),
    port,
    [
      from(atom.create("binary")),
      from(#(atom.create("active"), False)),
    ],
    1000,
  )
}
