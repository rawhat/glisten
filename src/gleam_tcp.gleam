import gleam/erlang
// import gleam/iterator
// import gleam/otp/process
import gleam_tcp/http
// import gleam_tcp/tcp.{receiver_to_iterator, start_acceptor}
import gleam_tcp/tcp.{start_acceptor}

pub fn main() {
  // let #(_sender, receiver) = process.new_channel()

  assert Ok(socket) = tcp.do_listen_tcp(8001, [])

  assert Ok(_sender1) = start_acceptor(socket, http.ok)
  assert Ok(_sender2) = start_acceptor(socket, http.ok)

  erlang.sleep_forever()

  // receiver
  // |> receiver_to_iterator
  // |> iterator.map(fn(msg) {
  //   io.println("i got a message from the iter")
  //   io.debug(msg)
  // })
  // |> iterator.run
}
