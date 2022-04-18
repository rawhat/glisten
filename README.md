# glisten

This is a gleam wrapper around `gen_tcp` loosely based on [ThousandIsland](https://github.com/mtrudel/thousand_island).

It uses the `gleam_otp` library to handle the supervisor and child processes.

The general structure is similar to ThousandIsland.  There is a supervisor that
manages a pool of acceptors.  Each acceptor will block on `accept` until a
connection is opened.  The acceptor will then spawn a handler process and
then block again on `accept`.

The handler function loops on messages received from the socket.  You can define
a handler with a function of the following type:

```gleam
fn(HandlerMessage, Socket) -> actor.Next(Socket)
```

This gives you access to the socket if you want to `send` to it in response.  I
think right now I don't have this set up where you can send to the socket
unprovoked?  So that seems like something I'll need to change... imminently.

## Examples

Just some basic handler examples that do also exist in this repo, but probably
won't once it's actually in better shape.

#### HTTP Hello World
```gleam
pub fn ok(_msg: HandlerMessage, sock: Socket) -> actor.Next(Socket) {
  assert Ok(resp) =
    "hello, world!"
    |> bit_string.from_string
    |> http_response(200, _)
    |> bit_string.to_string

  resp
  |> charlist.from_string
  |> send(sock, _)

  actor.Stop(process.Normal)
}
```

#### Full HTTP echo handler
```gleam
pub fn handler(req: Request(BitString)) -> Response(BitString) {
  response.new(200)
  |> response.set_body(req.body)
}
pub fn main() {
  assert Ok(socket) = tcp.do_listen_tcp(8000, [])
  try _ = tcp.start_acceptor_pool(socket, make_handler(handler), 10)

  Ok(erlang.sleep_forever())
}
```

## Notes

This is still very rough.  There are no tests, and as noted above you can't just
send where you implement it.

In some [not-very-scientific benchmarking](https://gist.github.com/rawhat/11ab57ef8dde4170304adc01c8c05a99), it seemed to do roughly as well as
ThousandIsland.  I am just using that as a reference point, certainly not trying
to draw any comparisons any time soon!
