pub type SocketReason {
  Closed
  Timeout
}

pub opaque type ListenSocket {
  ListenSocket
}

pub opaque type Socket {
  Socket
}

pub type Transport {
  Tcp
  Ssl(certfile: String, keyfile: String)
}
