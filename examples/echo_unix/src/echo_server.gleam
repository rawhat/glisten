import gleam/bytes_tree
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import glisten.{Packet}
import logging

pub fn main() {
  let listener_name = process.new_name("glisten_listener")
  let connection_factory_name = process.new_name("glisten_connection_factory")

  logging.configure()
  logging.set_level(logging.Debug)

  let assert Ok(_server) =
    glisten.new(
      listener_name,
      connection_factory_name,
      fn(_conn) { #(Nil, None) },
      fn(state, msg, conn) {
        logging.log(logging.Info, "Client connected via unix socket")

        let assert Packet(msg) = msg
        let assert Ok(_) = glisten.send(conn, bytes_tree.from_bit_array(msg))
        glisten.continue(state)
      },
    )
    |> glisten.with_ipv6
    |> glisten.start_unix("/tmp/test.sock")

  let assert glisten.UnixSocketAddress(path:) =
    glisten.get_server_info(process.named_subject(listener_name), 5000)

  io.println("Listening on " <> path)

  process.sleep_forever()
}
