-module(tcp_ffi).
-export([controlling_process/2, send/2, set_opts/2]).

send(Socket, Packet) ->
  case gen_tcp:send(Socket, Packet) of
    ok -> {ok, nil};
    Res -> Res
  end.

set_opts(Socket, Options) ->
  case inet:setopts(Socket, Options) of
    ok -> {ok, nil};
    {error, Reason} -> {error, Reason}
  end.

controlling_process(Socket, Pid) ->
  case gen_tcp:controlling_process(Socket, Pid) of
    ok -> {ok, nil};
    {error, Reason} -> {error, Reason}
  end.
