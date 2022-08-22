import gleam/bit_builder
import gleam/dynamic
import gleam/erlang/process
import gleam/otp/actor
import gleeunit
import gleeunit/should
import glisten/acceptor
import glisten/handler
import glisten/socket/options
import glisten/tcp
import glisten
import tcp_client

pub fn main() {
  gleeunit.main()
}

type Msg {
  Connected
  Response(BitString)
}

pub fn it_echoes_messages_test() {
  let client_subject = process.new_subject()
  let _server =
    process.start(
      fn() {
        assert Nil = process.send(client_subject, Connected)
        assert Ok(listener) =
          tcp.listen(9999, [options.ActiveMode(options.Passive)])
        assert Ok(socket) = tcp.accept(listener)
        let loop = fn() {
          assert Ok(msg) = tcp.receive_timeout(socket, 0, 200)
          process.send(client_subject, Response(msg))
        }
        loop()
      },
      False,
    )

  assert Ok(Connected) = process.receive(client_subject, 200)

  let client = tcp_client.connect()
  assert Ok(_) =
    tcp.send(client, bit_builder.from_bit_string(<<"hi mom":utf8>>))
  assert Ok(Response(resp)) = process.receive(client_subject, 200)

  should.equal(resp, <<"hi mom":utf8>>)
}

pub fn it_accepts_from_the_pool_test() {
  let client_sender = process.new_subject()
  assert Ok(Nil) =
    handler.func(fn(msg, state) {
      assert Ok(_) = tcp.send(state.socket, bit_builder.from_bit_string(msg))
      actor.Continue(state)
    })
    |> acceptor.new_pool
    |> acceptor.with_pool_size(1)
    |> glisten.serve(9999, _)

  let _client_process =
    process.start(
      fn() {
        let client_selector =
          process.selecting_anything(
            process.new_selector(),
            dynamic.unsafe_coerce,
          )
        let client = tcp_client.connect()
        assert Ok(_) =
          tcp.send(client, bit_builder.from_bit_string(<<"hi mom":utf8>>))
        assert Ok(#(_tcp, _port, msg)) = process.select(client_selector, 200)
        process.send(client_sender, msg)
      },
      False,
    )

  assert Ok(msg) = process.receive(client_sender, 200)

  should.equal(msg, <<"hi mom":utf8>>)
}
