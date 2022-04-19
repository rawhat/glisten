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

You can kind of do whatever you want.

I didn't test this, to be honest.  I think this should work?

```gleam
try listener =
  tcp.listen(
    8000,
    [
      tcp.Active(
        False
        |> dynamic.from
        |> dynamic.unsafe_coerce,
      ),
    ],
  )
try socket = tcp.accept(listener)
try msg = tcp.do_receive(socket, 0)
io.println("got a msg")
io.debug(msg)
```

See [dew](https://github.com/rawhat/dew) for some better examples.
