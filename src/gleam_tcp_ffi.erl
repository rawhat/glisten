-module(gleam_tcp_ffi).
-export([decode_packet/3, send/2]).

decode_packet(Type, Packet, Opts) ->
  case erlang:decode_packet(Type, Packet, Opts) of
    {ok, http_eoh, Rest} -> {ok, {end_of_headers, Rest}};
    {ok, Binary, Rest} -> {ok, {binary_data, Binary, Rest}};
    {more, Length} when Length =:= undefined -> {ok, {more_data, none}};
    {more, Length} -> {ok, {more_data, {some, Length}}};
    {error, Reason} -> {error, Reason}
  end.

send(Socket, Packet) ->
  case gen_tcp:send(Socket, Packet) of
    ok -> {ok, nil};
    Res -> Res
  end.
