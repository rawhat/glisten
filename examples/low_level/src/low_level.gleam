import gleam/io
import gleam/result
import glisten/socket/options.{ActiveMode, Passive}
import glisten/tcp
import logging

pub fn main() {
  logging.configure()

  use listener <- result.then(tcp.listen(8000, [ActiveMode(Passive)]))
  use socket <- result.then(tcp.accept(listener))
  use msg <- result.then(tcp.receive(socket, 0))
  io.debug(#("got a msg", msg))

  Ok(Nil)
}
