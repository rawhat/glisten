import gleam/bytes_tree
import gleam/erlang/process
import gleam/int
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
        let assert Ok(glisten.TcpSocketAddress(port:, ip_address:)) =
          glisten.get_connection_info(conn)
        logging.log(
          logging.Info,
          "Client connected at "
            <> glisten.ip_address_to_string(ip_address)
            <> " at port "
            <> int.to_string(port),
        )

        let assert Packet(msg) = msg
        let assert Ok(_) = glisten.send(conn, bytes_tree.from_bit_array(msg))
        glisten.continue(state)
      },
    )
    |> glisten.bind("localhost")
    |> glisten.with_ipv6
    |> glisten.start(0)

  let assert glisten.TcpSocketAddress(port:, ip_address:) =
    glisten.get_server_info(process.named_subject(listener_name), 5000)

  io.println(
    "Listening on "
    <> glisten.ip_address_to_string(ip_address)
    <> " at port "
    <> int.to_string(port),
  )

  process.sleep_forever()
}
