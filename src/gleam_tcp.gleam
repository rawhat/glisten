import gleam/erlang
import gleam_tcp/http
import gleam_tcp/tcp

pub fn main() {
  assert Ok(socket) = tcp.do_listen_tcp(8001, [])
  try _ = tcp.start_acceptor_pool(socket, http.ok, 10)

  Ok(erlang.sleep_forever())
}
