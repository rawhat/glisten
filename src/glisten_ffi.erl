-module(glisten_ffi).

-export([parse_address/1]).

parse_address(Address) ->
  case inet:parse_address(Address) of
    {ok, {A, B, C, D}} ->
      {ok, {ip_v4, A, B, C, D}};
    {ok, {A, B, C, D, E, F, G, H}} ->
      {ok, {ip_v6, A, B, C, D, E, F, G, H}};
    {error, _Reason} ->
      {error, nil}
  end.
