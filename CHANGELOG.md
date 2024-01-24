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
