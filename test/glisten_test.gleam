import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleeunit
import gleeunit/should
import glisten.{IpV6, Packet}
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
    process.spawn(fn() {
      let assert Ok(listener) =
        tcp.listen(54_321, [options.ActiveMode(options.Passive)])
      let Nil = process.send(client_subject, Connected)
      let assert Ok(socket) = tcp.accept(listener)
      let loop = fn() {
        let assert Ok(msg) = tcp.receive_timeout(socket, 0, 200)
        process.send(client_subject, Response(msg))
      }
      loop()
    })

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
    glisten.handler(fn(_conn) { #(Nil, None) }, fn(state, msg, conn) {
      let assert Packet(msg) = msg
      let assert Ok(_) = tcp.send(conn.socket, bytes_tree.from_bit_array(msg))
      actor.continue(state)
    })
    |> glisten.with_pool_size(1)
    |> glisten.serve(54_321)

  let _client_process =
    process.spawn(fn() {
      let client_selector =
        process.select_other(
          process.new_selector(),
          decode.run(_, {
            use tcp <- decode.field(0, decode.dynamic)
            use port <- decode.field(1, decode.dynamic)
            use msg <- decode.field(2, decode.bit_array)
            decode.success(#(tcp, port, msg))
          }),
        )
      let client = tcp_client.connect(54_321)
      let assert Ok(_) =
        tcp.send(client, bytes_tree.from_bit_array(<<"hi mom":utf8>>))
      let msg = process.selector_receive(client_selector, 200)
      let assert Ok(Ok(#(_tcp, _port, msg))) = msg
      process.send(client_sender, msg)
    })

  let assert Ok(msg) = process.receive(client_sender, 200)

  should.equal(msg, <<"hi mom":utf8>>)
}

pub fn ip_address_to_string_test() {
  use #(ip, expected) <- list.each([
    #(IpV6(0, 0, 0, 0, 0, 0, 0, 1), "::1"),
    #(IpV6(0, 0, 0, 0, 0, 0, 0, 0), "::"),
    #(IpV6(0x2001, 0xdb8, 0, 0, 1, 0, 0, 0), "2001:db8:0:0:1::"),
    #(IpV6(0x2001, 0xdb8, 1, 1, 1, 1, 0, 1), "2001:db8:1:1:1:1:0:1"),
    #(IpV6(0x2001, 0xdb8, 0, 0, 1, 0, 0, 1), "2001:db8::1:0:0:1"),
    #(IpV6(0x2001, 0xdb8, 0, 0, 0, 0, 2, 1), "2001:db8::2:1"),
  ])

  glisten.ip_address_to_string(ip)
  |> should.equal(expected)
}
