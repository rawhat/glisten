import gleam/bytes_tree
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/function
import gleam/option.{None}
import glisten
import glisten/internal/listener
import glisten/socket
import glisten/tcp
import tcp_client

type TraceSession

type TraceProcesses {
  New
}

@external(erlang, "trace", "session_create")
fn create_trace_session(
  name: atom.Atom,
  tracer: process.Pid,
  options: List(Nil),
) -> TraceSession

@external(erlang, "trace", "process")
fn trace_processes(
  session: TraceSession,
  processes: TraceProcesses,
  enabled enabled: Bool,
  flags flags: List(atom.Atom),
) -> Int

@external(erlang, "trace", "session_destroy")
fn destroy_trace_session(session: TraceSession) -> Bool

@external(erlang, "gleam_erlang_ffi", "identity")
fn to_dynamic(value: a) -> Dynamic

fn listener_registration_decoder(
  name: process.Name(listener.Message),
) -> decode.Decoder(Nil) {
  use event <- decode.field(2, atom.decoder())
  use registered_name <- decode.field(3, decode.dynamic)
  case event == atom.create("register") && registered_name == to_dynamic(name) {
    True -> decode.success(Nil)
    False -> decode.failure(Nil, expected: "the listener's registration")
  }
}

fn wait_for_listener_registration(
  events: process.Selector(Result(Nil, List(decode.DecodeError))),
) -> Nil {
  let assert Ok(event) = process.selector_receive(events, within: 1000)
  case event {
    Ok(Nil) -> Nil
    Error(_unrelated_event) -> wait_for_listener_registration(events)
  }
}

fn stop_server(pid: process.Pid) -> Nil {
  process.unlink(pid)
  let monitor = process.monitor(pid)
  process.send_exit(pid)
  let assert Ok(process.ProcessDown(pid: stopped_pid, ..)) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, function.identity)
    |> process.selector_receive(within: 1000)
  assert stopped_pid == pid
}

pub fn a_listener_failure_restarts_acceptors_and_keeps_connections_test() {
  let listener_name = process.new_name("glisten_listener_recovery_test")
  let assert Ok(server) =
    glisten.new(
      fn(_connection) { #(Nil, None) },
      fn(state, message, connection) {
        let assert glisten.Packet(packet) = message
        let assert Ok(Nil) =
          glisten.send(connection, bytes_tree.from_bit_array(packet))
        glisten.continue(state)
      },
    )
    |> glisten.with_listener_name(listener_name)
    |> glisten.with_pool_size(1)
    |> glisten.start(0)
  let assert glisten.TcpServerInfo(port:, ..) =
    glisten.get_server_info(listener_name, 1000)
  let assert Ok(original) = tcp_client.connect_passive(port)
  let assert Ok(Nil) = tcp.send(original, bytes_tree.from_string("before"))
  let assert Ok(<<"before":utf8>>) = tcp.receive_timeout(original, 6, 1000)

  let session =
    create_trace_session(
      atom.create("glisten_listener_recovery_test"),
      process.self(),
      [],
    )
  let _ =
    trace_processes(session, New, enabled: True, flags: [atom.create("procs")])
  let registration = listener_registration_decoder(listener_name)
  let events =
    process.new_selector()
    |> process.select_record(atom.create("trace"), 3, decode.run(
      _,
      registration,
    ))
  let assert Ok(listener_pid) = process.named(listener_name)
  process.kill(listener_pid)
  wait_for_listener_registration(events)
  assert destroy_trace_session(session)

  let assert glisten.TcpServerInfo(port: replacement_port, ..) =
    glisten.get_server_info(listener_name, 1000)
  let assert Ok(replacement) = tcp_client.connect_passive(replacement_port)
  let assert Ok(Nil) = tcp.send(replacement, bytes_tree.from_string("new"))
  let assert Ok(<<"new":utf8>>) = tcp.receive_timeout(replacement, 3, 1000)
  let assert Ok(Nil) = tcp.send(original, bytes_tree.from_string("after"))
  let assert Ok(<<"after":utf8>>) = tcp.receive_timeout(original, 5, 1000)
  let assert Ok(Nil) = tcp.close(replacement)
  let assert Ok(Nil) = tcp.close(original)
  stop_server(server.pid)
}

pub fn stopping_accepts_keeps_an_accepted_connection_alive_test() {
  let held = process.new_subject()
  let listener_name = process.new_name("glisten_shutdown_test")
  let assert Ok(server) =
    glisten.new(
      fn(_connection) { #(process.new_subject(), None) },
      fn(release, message, connection) {
        let assert glisten.Packet(packet) = message
        process.send(held, release)
        let assert Ok(Nil) = process.receive(release, within: 1000)
        let assert Ok(Nil) =
          glisten.send(connection, bytes_tree.from_bit_array(packet))
        glisten.stop()
      },
    )
    |> glisten.with_listener_name(listener_name)
    |> glisten.with_pool_size(2)
    |> glisten.start_with_listener(0)

  let server_info = glisten.get_server_info(listener_name, 1000)
  let assert Ok(listener_pid) = process.named(listener_name)
  let assert glisten.TcpServerInfo(port:, ..) = server_info
  let assert Ok(client) = tcp_client.connect_passive(port)
  let assert Ok(Nil) = tcp.send(client, bytes_tree.from_string("held"))
  let assert Ok(release) = process.receive(held, within: 1000)

  assert glisten.stop_accepting(server.listener, within: 1000)
    == Ok(server_info)
  let assert Error(socket.Econnrefused) = tcp_client.connect_passive(port)
  assert glisten.stop_accepting(server.listener, within: 1000)
    == Ok(server_info)

  process.send(release, Nil)
  let assert Ok(<<"held":utf8>>) = tcp.receive_timeout(client, 4, 1000)
  let assert Error(socket.Closed) = tcp.receive_timeout(client, 0, 1000)
  let assert Ok(Nil) = tcp.close(client)

  assert process.is_alive(server.started.pid)
  stop_server(server.started.pid)

  let assert Error(glisten.StopAcceptingError(
    listener_name: stopped_name,
    listener_pid: stopped_pid,
    server_info: stopped_info,
    reason: glisten.ListenerExited(reason: process.Abnormal(reason)),
  )) = glisten.stop_accepting(server.listener, within: 1000)
  assert stopped_name == listener_name
  assert stopped_pid == listener_pid
  assert stopped_info == server_info
  let assert Ok(reason) = decode.run(reason, atom.decoder())
  assert atom.to_string(reason) == "noproc"
}
