import gleam/bytes_builder
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import glisten.{Packet}

pub fn main() {
  let assert Ok(_) =
    glisten.handler(fn() { #(Nil, None) }, fn(msg, state, conn) {
      let assert Packet(msg) = msg
      let assert Ok(_) = glisten.send(conn, bytes_builder.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.serve(3000)

  process.sleep_forever()
}
