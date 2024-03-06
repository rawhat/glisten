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

pub fn connect(port: Int) -> Socket {
  let assert Ok(client) =
    tcp_connect(charlist.from_string("localhost"), port, [
      dynamic.from(atom.create_from_string("binary")),
    ])
  client
}
