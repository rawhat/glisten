import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/list

/// Mode for the socket.  Currently `list` is not supported
pub type SocketMode {
  Binary
}

/// Mapping to the `{active, _}` option
pub type ActiveState {
  Once
  Passive
  Count(Int)
  Active
}

/// Options for the TCP socket
pub type TcpOption {
  Backlog(Int)
  Nodelay(Bool)
  Linger(#(Bool, Int))
  SendTimeout(Int)
  SendTimeoutClose(Bool)
  Reuseaddr(Bool)
  ActiveMode(ActiveState)
  Mode(SocketMode)
  // TODO:  Probably should adjust the type here to only allow this for SSL
  Certfile(String)
  Keyfile(String)
  AlpnPreferredProtocols(List(String))
  Inet6
  Buffer(Int)
}

pub fn to_dict(options: List(TcpOption)) -> Dict(Dynamic, Dynamic) {
  let opt_decoder = dynamic.tuple2(dynamic.dynamic, dynamic.dynamic)

  options
  |> list.map(fn(opt) {
    case opt {
      ActiveMode(Passive) ->
        dynamic.from(#(atom.create_from_string("active"), False))
      ActiveMode(Active) ->
        dynamic.from(#(atom.create_from_string("active"), True))
      ActiveMode(Count(n)) ->
        dynamic.from(#(atom.create_from_string("active"), n))
      ActiveMode(Once) ->
        dynamic.from(#(
          atom.create_from_string("active"),
          atom.create_from_string("once"),
        ))
      other -> dynamic.from(other)
    }
  })
  |> list.filter_map(opt_decoder)
  |> dict.from_list
}

pub const default_options = [
  Backlog(1024), Nodelay(True), SendTimeout(30_000), SendTimeoutClose(True),
  Reuseaddr(True), Mode(Binary), ActiveMode(Passive),
]

pub fn merge_with_defaults(options: List(TcpOption)) -> List(TcpOption) {
  let overrides = to_dict(options)

  default_options
  |> to_dict
  |> dict.merge(overrides)
  |> dict.to_list
  |> list.map(dynamic.from)
  |> add_inet6
}

@external(erlang, "glisten_ffi", "add_inet6")
fn add_inet6(options: List(Dynamic)) -> List(TcpOption)
