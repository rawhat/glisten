import gleam/bit_string
import gleam/string_builder.{StringBuilder}
import gleam/bit_string
import gleam/http/response.{Response}
import gleam/int
// import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/otp/process
import gleam/result
import gleam_tcp/tcp.{HandlerMessage, Socket, send}

pub fn code_to_string(code: Int) -> String {
  case code {
    200 -> "Ok"
    _ -> "Unknown"
  }
}

pub fn headers(resp: Response(BitString)) -> StringBuilder {
  list.fold(
    resp.headers,
    string_builder.from_string(""),
    fn(builder, tup) {
      let #(header, value) = tup

      string_builder.from_strings([header, ": ", value, "\r\n"])
      |> string_builder.append_builder(builder, _)
    },
  )
}

pub fn to_string(resp: Response(BitString)) -> BitString {
  let body_builder = case bit_string.byte_size(resp.body) {
    0 -> string_builder.from_string("")
    _size ->
      resp.body
      |> bit_string.to_string
      |> result.unwrap("")
      |> string_builder.from_string
      |> string_builder.append("\r\n")
  }

  "HTTP/1.1 "
  |> string_builder.from_string
  |> string_builder.append(int.to_string(resp.status))
  |> string_builder.append("\r\n")
  |> string_builder.append_builder(headers(resp))
  |> string_builder.append("\r\n\r\n")
  |> string_builder.append_builder(body_builder)
  |> string_builder.to_string
  |> bit_string.from_string
}

pub fn http_response(status: Int, body: BitString) -> BitString {
  response.new(status)
  |> response.set_body(body)
  |> response.prepend_header("Content-Type", "text/plain")
  |> response.prepend_header(
    "Content-Length",
    body
    |> bit_string.byte_size
    |> fn(size) { size + 1 }
    |> int.to_string,
  )
  |> response.prepend_header("Connection", "close")
  |> to_string
}

pub fn ok(_msg: HandlerMessage, sock: Socket) -> actor.Next(Socket) {
  // io.debug("i am in the ok method!")
  // assert AcceptorState(_sender, Some(sock)) = state

  "hello, world!"
  |> bit_string.from_string
  |> http_response(200, _)
  // |> io.debug
  |> send(sock, _)

  actor.Stop(process.Normal)
}
