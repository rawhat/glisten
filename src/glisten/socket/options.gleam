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

pub type Interface {
  Address(IpAddress)
  Any
  Loopback
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
  Ipv6
  Buffer(Int)
  Ip(Interface)
}

pub fn to_dict(options: List(TcpOption)) -> Dict(Dynamic, Dynamic) {
  let opt_decoder = dynamic.tuple2(dynamic.dynamic, dynamic.dynamic)

  let active = atom.create_from_string("active")
  let ip = atom.create_from_string("ip")

  options
  |> list.map(fn(opt) {
    case opt {
      ActiveMode(Passive) -> dynamic.from(#(active, False))
      ActiveMode(Active) -> dynamic.from(#(active, True))
      ActiveMode(Count(n)) -> dynamic.from(#(active, n))
      ActiveMode(Once) ->
        dynamic.from(#(active, atom.create_from_string("once")))
      Ip(Address(IpV4(a, b, c, d))) ->
        dynamic.from(#(ip, dynamic.from(#(a, b, c, d))))
      Ip(Address(IpV6(a, b, c, d, e, f, g, h))) ->
        dynamic.from(#(ip, dynamic.from(#(a, b, c, d, e, f, g, h))))
      Ip(Any) -> dynamic.from(#(ip, atom.create_from_string("any")))
      Ip(Loopback) -> dynamic.from(#(ip, atom.create_from_string("loopback")))
      Ipv6 -> dynamic.from(atom.create_from_string("inet6"))
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

  let has_ipv6 = list.contains(options, Ipv6)

  default_options
  |> to_dict
  |> dict.merge(overrides)
  |> dict.to_list
  |> list.map(dynamic.from)
  |> fn(opts) {
    case has_ipv6 {
      True -> [dynamic.from(atom.create_from_string("inet6")), ..opts]
      _ -> opts
    }
  }
  |> unsafe_coerce
}

@external(erlang, "gleam@function", "identity")
fn unsafe_coerce(value: a) -> b

pub type IpAddress {
  IpV4(Int, Int, Int, Int)
  IpV6(Int, Int, Int, Int, Int, Int, Int, Int)
}
