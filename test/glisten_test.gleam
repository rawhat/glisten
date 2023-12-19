import gleam/bytes_builder
import gleam/dynamic
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import gleeunit
import gleeunit/should
import glisten/socket/options
import glisten/tcp
import glisten.{Packet}
import tcp_client

pub fn main() {
  gleeunit.main()
}

type Msg {
  Connected
  Response(BitArray)
}

pub fn it_echoes_messages_test() {
  let client_subject = process.new_subject()
  let _server =
    process.start(
      fn() {
        let assert Nil = process.send(client_subject, Connected)
        let assert Ok(listener) =
          tcp.listen(9999, [options.ActiveMode(options.Passive)])
        let assert Ok(socket) = tcp.accept(listener)
        let loop = fn() {
          let assert Ok(msg) = tcp.receive_timeout(socket, 0, 200)
          process.send(client_subject, Response(msg))
        }
        loop()
      },
      False,
    )

  let assert Ok(Connected) = process.receive(client_subject, 200)

  let client = tcp_client.connect(9999)
  let assert Ok(_) =
    tcp.send(client, bytes_builder.from_bit_array(<<"hi mom":utf8>>))
  let assert Ok(Response(resp)) = process.receive(client_subject, 200)

  should.equal(resp, <<"hi mom":utf8>>)
}

pub fn it_accepts_from_the_pool_test() {
  let client_sender = process.new_subject()
  let assert Ok(Nil) =
    glisten.handler(fn() { #(Nil, None) }, fn(msg, state, conn) {
      let assert Packet(msg) = msg
      let assert Ok(_) =
        tcp.send(conn.socket, bytes_builder.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.with_pool_size(1)
    |> glisten.serve(9998)

  let _client_process =
    process.start(
      fn() {
        let client_selector =
          process.selecting_anything(
            process.new_selector(),
            dynamic.unsafe_coerce,
          )
        let client = tcp_client.connect(9998)
        let assert Ok(_) =
          tcp.send(client, bytes_builder.from_bit_array(<<"hi mom":utf8>>))
        let assert Ok(#(_tcp, _port, msg)) =
          process.select(client_selector, 200)
        process.send(client_sender, msg)
      },
      False,
    )

  let assert Ok(msg) = process.receive(client_sender, 200)

  should.equal(msg, <<"hi mom":utf8>>)
}
