import gleam/bytes_builder
import gleam/erlang/atom.{type Atom}
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import glisten.{Packet}

@external(erlang, "logger", "update_primary_config")
fn logger_update_primary_config(config: Dict(Atom, Atom)) -> Result(Nil, any)

pub fn main() {
  logger_update_primary_config(
    dict.from_list([
      #(atom.create_from_string("level"), atom.create_from_string("debug")),
    ]),
  )

  let assert Ok(_) =
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(msg, state, conn) {
      let assert Packet(msg) = msg
      let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.serve(3000)

  process.sleep_forever()
}
