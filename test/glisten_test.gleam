import gleam/bytes_tree
import gleam/dynamic
import gleam/erlang/process
import gleam/option.{None}
import gleam/otp/actor
import gleeunit
import gleeunit/should
import glisten.{Packet}
import glisten/socket/options
import glisten/tcp
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
        let assert Ok(listener) =
          tcp.listen(54_321, [options.ActiveMode(options.Passive)])
        let Nil = process.send(client_subject, Connected)
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

  let client = tcp_client.connect(54_321)
  let assert Ok(_) =
    tcp.send(client, bytes_tree.from_bit_array(<<"hi mom":utf8>>))
  let assert Ok(Response(resp)) = process.receive(client_subject, 200)

  should.equal(resp, <<"hi mom":utf8>>)
}

pub fn it_accepts_from_the_pool_test() {
  let client_sender = process.new_subject()
  let assert Ok(_server) =
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(msg, state, conn) {
      let assert Packet(msg) = msg
      let assert Ok(_) = tcp.send(conn.socket, bytes_tree.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.with_pool_size(1)
    |> glisten.serve(54_321)

  let _client_process =
    process.start(
      fn() {
        let client_selector =
          process.selecting_anything(
            process.new_selector(),
            dynamic.tuple3(dynamic.dynamic, dynamic.dynamic, dynamic.bit_array),
          )
        let client = tcp_client.connect(54_321)
        let assert Ok(_) =
          tcp.send(client, bytes_tree.from_bit_array(<<"hi mom":utf8>>))
        let msg = process.select(client_selector, 200)
        let assert Ok(Ok(#(_tcp, _port, msg))) = msg
        process.send(client_sender, msg)
      },
      False,
    )

  let assert Ok(msg) = process.receive(client_sender, 200)

  should.equal(msg, <<"hi mom":utf8>>)
}
