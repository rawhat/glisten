import gleam/bytes_tree
import gleam/erlang/process
import gleam/io
import gleam/option.{None}
import glisten.{Packet}
import logging

pub fn main() {
  let listener_name = process.new_name("glisten_listener")

  logging.configure()
  logging.set_level(logging.Debug)

  let assert Ok(_server) =
    glisten.new(fn(_conn) { #(Nil, None) }, fn(state, msg, conn) {
      logging.log(logging.Info, "Client connected via unix socket")

      let assert Packet(msg) = msg
      let assert Ok(_) = glisten.send(conn, bytes_tree.from_bit_array(msg))
      glisten.continue(state)
    })
    |> glisten.with_ipv6
    |> glisten.with_listener_name(listener_name)
    |> glisten.start_unix("/tmp/test.sock")

  let assert glisten.UnixServerInfo(path:) =
    glisten.get_server_info(listener_name, 5000)

  io.println("Listening on " <> path)

  process.sleep_forever()
}
