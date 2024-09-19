# v6.0.0

- Support specifying the listening interface
- Stop listening on IPv6 by default, instead preferring a builder function to
enable it
- Some tweaks to the shape of the `glisten/socket/options` module values
- Moved the `IpAddress` type to the `glisten/socket/options` module

# v5.0.0

- Move `transport.listen` method out of calling process into separate process
managed by supervisor
- Fix flaky test due to ordering
- Update connection info functions for getting IP and port (both client and
server)

# v4.0.0

- Partially revert the `serve`/`serve_ssl` change noted below.  These functions
  are now available at `start_server` and `start_ssl_server` since they add some
  boilerplate for accessing the underlying supervisor.
- Update the mechanism for accessing the client IP and port.  Previously, this
  was provided as a 4-tuple on the connection.  However, this value could be an
  IPv6, or an IPv4-mapped IPv6 value.  Also, to avoid the overhead of doing this
  every time, a `get_client_info` function has been added to get this
  information on demand.

# v3.0.0

- Set `buffer` on socket based on `recvbuf` per erlang documentation
- Use `logging` library instead of custom logger
- Add some (unused) telemetry events
- Add flag for `http2` support to handler for `mist`
- Update `serve`/`serve_ssl` methods to return `Server` record. This allows for
  accessing an OS-assigned port if 0 is provided.  It will also help enable
  graceful shutdown later
- Fix some function deprecation warnings in the standard library

# v2.0.0

- Pass `Connection` as argument in `on_init`
    - This actually mirrors the `mist` WebSocket API and was clearly just an
    oversight on my part

# v1.0.0

- Remove default `linger` option on sockets
- Move a bunch of stuff into `internal`
- Refactor the `transport` module (and associated types)

# v0.11.0

- Updated for Gleam ~v1.0 and `gleam_stdlib` >= 0.35

# v0.9.3

- Updated for Gleam v0.33.0.
- The `options.to_map` function has been renamed to `options.to_dict`.
- Return `Subject` from pool supervisor

# v0.9.1

- Pass state value to `on_close` handler
- Add support for IPv6 to socket options

# v0.9.0

- Refactor API to mirror `mist` structure
- Enable support for user-defined messages in addition to internal

# v0.8.2

- Upgrade `gleam_otp` to v0.7

# v0.8.1

- Upgrade `gleam_stdlib`, `gleam_erlang`
- Fix incorrect SSL client IP accessor method

# v0.8.0

- Run `gleam fix` for v0.30
- Add field to handler state with client IP
- Replace `unsafe_coerce` in message selector with safer
`selecting_recordN` methods

# v0.7.0

- Upgrade `gleam_stdlib`, `gleam_erlang`
- Update syntax for Gleam v0.27
- Revert inadvertent change to add `ALPN` support

# v0.6.9

- Fix extra wrapping of `{ok, _}` in SSL FFI

# v0.6.8

- Fix typo in SSL `negoiated_protocol` method

# v0.6.7

- Return correct `Result` from `shutdown`
- Expand socket error values
- Return correct `Result` from `close`
