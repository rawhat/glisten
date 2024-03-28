import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/string
import logging

pub type Data {
  Data(latency: Int, metadata: Dict(String, Dynamic))
}

pub type Event {
  Glisten

  Handshake
  HandlerLoop

  Listener

  Acceptor
  HandlerStart
}

pub fn log(
  path: List(Event),
  measurements: Dict(String, Dynamic),
  metadata: Dict(String, Dynamic),
  _config: List(config),
) -> Nil {
  logging.log(
    logging.Debug,
    string.inspect(path)
      <> " metadata: "
      <> string.inspect(metadata)
      <> ", measurements: "
      <> string.inspect(measurements),
  )
}

@external(erlang, "telemetry", "span")
pub fn span(
  path: List(Event),
  metadata: Dict(String, Dynamic),
  wrapping: fn() -> return,
) -> return

@external(erlang, "telemetry", "attach_many")
pub fn attach_many(
  id: String,
  path: List(List(Event)),
  handler: fn(
    List(Event),
    Dict(String, Dynamic),
    Dict(String, Dynamic),
    List(config),
  ) ->
    Nil,
  config: List(any),
) -> Nil
