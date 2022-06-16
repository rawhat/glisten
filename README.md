# glisten

This is a Gleam wrapper around `gen_tcp`. I got a great amount of inspiration
from [ThousandIsland](https://github.com/mtrudel/thousand_island).

See the docs [here](https://hexdocs.pm/glisten/).

It uses the `gleam_otp` library to handle the supervisor and child processes.

`glisten` provides a supervisor which manages a pool of acceptors. Each acceptor
will block on `accept` until a connection is opened.  The acceptor will then
spawn a handler process and then block again on `accept`.

The most obvious entrypoint is `glisten/tcp.{handler, serve}` where `serve`
listens for TCP connections on a given port.  It also takes a handler function
wrapper which you can provide functionality to, and the state which each TCP
connection process will hold.  This takes the shape of:

```gleam
type HandlerFunc(data) =
  fn(BitString, LoopState(data)) -> actor.Next(LoopState(data))
```

`glisten` doesn't provide a public API for connected clients.  In order to hook
into the socket lifecyle, you can establish some functions which are called
for the opening and closing of the socket.  An example is provided below.

## Examples

Here is a basic echo server:

```gleam
pub fn main() {
  tcp.handler(fn(msg, state) {
    assert Ok(_) = tcp.send(state.socket, bit_builder.from_bit_string(msg))
    actor.Continue(state)
  })
  |> tcp.acceptor_pool
  |> serve(8080, _)
  |> result.map(fn(_) { erlang.sleep_forever() })
}
```

Managing connected clients can be handled similarly to this simple example:

```gleam
pub fn main() {
  // This function is omitted for brevity.  It simply manages a
  // `gleam/set.{Set}` of `Sender(HandlerMessage)`s that "broadcast" the
  // connect/disconnect events to all clients.
  assert Ok(connections) = start_connection_actor()

  tcp.handler(fn(msg, state) {
    assert Ok(_) = tcp.send(state.socket, bit_builder.from_bit_string(msg))
    actor.Continue(state)
  })
  |> tcp.acceptor_pool
  |> tcp.with_init(fn(sender) {
    process.send(connections, Connected(sender))

    Nil
  })
  |> tcp.with_close(fn(sender) {
    process.send(connections, Disconnected(sender))

    Nil
  })
  |> serve(8080, _)
  |> result.map(fn(_) { erlang.sleep_forever() })
}
```

But you can also drop down to the lower level listen/accept flow if you'd prefer
to manage connections yourself, or only handle a small number at a time.

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
