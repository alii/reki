-module(reki_ets_ffi).
-export([
    new/1,
    insert/3,
    lookup/2,
    delete/2,
    to_dynamic/1,
    cast_subject/1,
    pdict_put/2,
    pdict_delete/1,
    new_unique_atom/0
]).

-spec pdict_put(term(), term()) -> nil.
pdict_put(Key, Value) ->
    erlang:put(Key, Value),
    nil.

-spec pdict_delete(term()) -> {ok, term()} | {error, nil}.
pdict_delete(Key) ->
    case erlang:erase(Key) of
        undefined -> {error, nil};
        Value -> {ok, Value}
    end.

-spec cast_subject(term()) -> term().
cast_subject(Value) ->
    Value.

-spec new_unique_atom() -> atom().
new_unique_atom() ->
    Suffix = integer_to_binary(erlang:unique_integer([positive])),
    Name = <<"reki$", Suffix/bits>>,
    binary_to_atom(Name).

-spec to_dynamic(term()) -> term().
to_dynamic(Value) ->
    Value.

-spec new(atom()) -> {ok, reference()} | {error, nil}.
new(Name) ->
    try
        Tid = ets:new(Name, [
            set,
            named_table,
            public,
            {read_concurrency, true}
        ]),
        {ok, Tid}
    catch
        error:badarg -> {error, nil}
    end.

-spec insert(atom(), term(), term()) -> {ok, nil} | {error, nil}.
insert(Name, Key, Value) ->
    try
        ets:insert(Name, {Key, Value}),
        {ok, nil}
    catch
        error:badarg -> {error, nil}
    end.

-spec lookup(atom(), term()) -> {some, term()} | none.
lookup(Name, Key) ->
    try
        case ets:lookup(Name, Key) of
            [{Key, Value}] -> {some, Value};
            [] -> none
        end
    catch
        error:badarg -> none
    end.

-spec delete(atom(), term()) -> {ok, nil} | {error, nil}.
delete(Name, Key) ->
    try
        ets:delete(Name, Key),
        {ok, nil}
    catch
        error:badarg -> {error, nil}
    end.
