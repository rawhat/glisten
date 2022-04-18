import gleam/erlang
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import glisten/http.{make_handler}
import glisten/tcp

pub fn handler(req: Request(BitString)) -> Response(BitString) {
  response.new(200)
  |> response.set_body(req.body)
}

pub fn main() {
  assert Ok(socket) = tcp.do_listen_tcp(8000, [])
  try _ = tcp.start_acceptor_pool(socket, make_handler(handler), 10)

  Ok(erlang.sleep_forever())
}
