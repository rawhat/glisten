# glisten

This is a Gleam wrapper around `gen_tcp` loosely based on [ThousandIsland](https://github.com/mtrudel/thousand_island).

It uses the `gleam_otp` library to handle the supervisor and child processes.

The general structure is similar to ThousandIsland.  There is a supervisor that
manages a pool of acceptors.  Each acceptor will block on `accept` until a
connection is opened.  The acceptor will then spawn a handler process and
then block again on `accept`.

The most obvious entrypoint is `glisten/tcp.{handler, serve}` where `serve`
listens for TCP connections on a given port.  It also takes a handler function
wrapper which you can provide functionality to, and the state which each TCP
connection process will hold.  This takes the shape of:

```gleam
type HandlerFunc(data) =
  fn(BitString, LoopState(data)) -> actor.Next(LoopState(data))
```

## Examples

Here is a basic echo server:

```gleam
pub fn main() {
  assert Ok(_) = serve(8080, tcp.handler(fn(msg, state) {
    assert Ok(_) = tcp.send(state.socket, bit_builder.from_bit_string(msg))
    actor.Continue(state)
  }), Nil)
  erlang.sleep_forever()
}
```

But you can also do whatever you want.

```gleam
pub fn main() {
  try listener = tcp.listen(8000, [ActiveMode(Passive)])
  try socket = tcp.accept(listener)
  try msg = tcp.receive(socket, 0)
  io.println("got a msg")
  io.debug(msg)

  Ok(Nil)
}
```

See [mist](https://github.com/rawhat/mist) for HTTP support built on top of
this library.
