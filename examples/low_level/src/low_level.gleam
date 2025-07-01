import gleam/result
import glisten/socket/options.{ActiveMode, Passive}
import glisten/tcp
import logging

pub fn main() {
  logging.configure()

  use listener <- result.try(tcp.listen(8000, [ActiveMode(Passive)]))
  use socket <- result.try(tcp.accept(listener))
  use msg <- result.try(tcp.receive(socket, 0))
  echo msg

  Ok(Nil)
}
