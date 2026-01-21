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

pub type TlsCerts {
  CertKeyFiles(certfile: String, keyfile: String)
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
  // TODO:  Probably should adjust the type here to only allow this for TLS
  CertKeyConfig(TlsCerts)
  AlpnPreferredProtocols(List(String))
  Ipv6
  Buffer(Int)
  Ip(Interface)
}

pub type ErlangTcpOption

@external(erlang, "glisten_ffi", "to_erl_tcp_options")
pub fn to_erl_options(options: List(TcpOption)) -> List(ErlangTcpOption)

pub const default_options = [
  Backlog(1024),
  Nodelay(True),
  SendTimeout(30_000),
  SendTimeoutClose(True),
  Reuseaddr(True),
  Mode(Binary),
  ActiveMode(Passive),
]

@external(erlang, "glisten_ffi", "merge_type_list")
pub fn merge_type_list(original: List(a), override: List(a)) -> List(a)

pub fn merge_with_defaults(options: List(TcpOption)) -> List(TcpOption) {
  merge_type_list(default_options, options)
}

pub type IpAddress {
  IpV4(Int, Int, Int, Int)
  IpV6(Int, Int, Int, Int, Int, Int, Int, Int)
}
