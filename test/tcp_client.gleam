import gleam/dynamic.{Dynamic}
import gleam/erlang/atom
import gleam/erlang/charlist.{Charlist}
import glisten/socket.{Socket}

@external(erlang, "gen_tcp", "connect")
fn tcp_connect(host: Charlist, port: Int, options: List(Dynamic)) -> Result(
  Socket,
  Nil,
)

pub fn connect() -> Socket {
  let assert Ok(client) =
    tcp_connect(
      charlist.from_string("localhost"),
      9999,
      [dynamic.from(atom.create_from_string("binary"))],
    )
  client
}
