import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/charlist.{type Charlist}
import glisten/socket.{type Socket}

@external(erlang, "gen_tcp", "connect")
fn tcp_connect(
  host: Charlist,
  port: Int,
  options: List(Dynamic),
) -> Result(Socket, Nil)

@external(erlang, "gleam@function", "identity")
fn from(value: a) -> Dynamic

pub fn connect(port: Int) -> Socket {
  let assert Ok(client) =
    tcp_connect(charlist.from_string("localhost"), port, [
      from(atom.create("binary")),
    ])
  client
}
