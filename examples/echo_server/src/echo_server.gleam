import gleam/bytes_builder
import gleam/dict.{type Dict}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import glisten.{Packet}
import logging

@external(erlang, "logger", "update_primary_config")
fn logger_update_primary_config(config: Dict(Atom, Atom)) -> Result(Nil, any)

pub fn main() {
  logging.configure()
  let _ =
    logger_update_primary_config(
      dict.from_list([
        #(atom.create_from_string("level"), atom.create_from_string("debug")),
      ]),
    )

  let assert Ok(server) =
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(msg, state, conn) {
      let assert Ok(#(ip, port)) = glisten.get_client_info(conn)
      logging.log(
        logging.Info,
        "Client connected at "
          <> string.inspect(ip)
          <> " at port "
          <> int.to_string(port),
      )
      let assert Packet(msg) = msg
      let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.start_server(0)

  let assert Ok(port) = glisten.get_port(server)

  io.println("Listening on port: " <> int.to_string(port))

  process.sleep_forever()
}
