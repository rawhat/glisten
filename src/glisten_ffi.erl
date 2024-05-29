-module(glisten_ffi).

-export([add_inet6/1]).

add_inet6(Options) ->
  [inet6 | Options].
