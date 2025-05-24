import gleam/bytes_tree
import gleam/dict.{type Dict}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/string
import glisten.{Packet}
import logging

@external(erlang, "logger", "update_primary_config")
fn logger_update_primary_config(config: Dict(Atom, Atom)) -> Result(Nil, any)

pub fn main() {
  let listener_name = process.new_name("glisten_listener")

  logging.configure()
  let _ =
    logger_update_primary_config(
      dict.from_list([#(atom.create("level"), atom.create("debug"))]),
    )

  let assert Ok(_server) =
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(state, msg, conn) {
      let assert Ok(info) = glisten.get_client_info(conn)
      logging.log(
        logging.Info,
        "Client connected at "
          <> string.inspect(info.ip_address)
          <> " at port "
          <> int.to_string(info.port),
      )
      let assert Packet(msg) = msg
      let assert Ok(_) = glisten.send(conn, bytes_tree.from_bit_array(msg))
      glisten.continue(state)
      // |> glisten.with_selector(...)
      // glisten.stop()
      // glisten.stop_abnormal()
    })
    |> glisten.bind("localhost")
    |> glisten.with_ipv6
    |> glisten.serve_with_listener_name(0, listener_name)

  let info = glisten.get_server_info(listener_name, 5000)

  io.println(
    "Listening on "
    <> glisten.ip_address_to_string(info.ip_address)
    <> " at port "
    <> int.to_string(info.port),
  )

  process.sleep_forever()
}
