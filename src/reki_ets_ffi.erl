-module(reki_ets_ffi).
-export([
    new/1,
    get_or_create/1,
    insert/3,
    lookup/2,
    delete/2,
    to_dynamic/1,
    cast_subject/1,
    pdict_put/2,
    pdict_delete/1
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

-spec to_dynamic(term()) -> term().
to_dynamic(Value) ->
    Value.

-spec new(binary()) -> {ok, nil} | {error, nil}.
new(NameBin) ->
    try
        Name = binary_to_atom(NameBin),
        _Tid = ets:new(Name, [
            set,
            named_table,
            public,
            {read_concurrency, true}
        ]),
        {ok, nil}
    catch
        error:badarg -> {error, nil}
    end.

-spec get_or_create(binary()) -> {ok, nil} | {error, nil}.
get_or_create(NameBin) ->
    try
        Name = binary_to_atom(NameBin),
        case ets:whereis(Name) of
            undefined ->
                _Tid = ets:new(Name, [
                    set,
                    named_table,
                    public,
                    {read_concurrency, true}
                ]),
                {ok, nil};
            _Tid ->
                {ok, nil}
        end
    catch
        error:badarg -> {error, nil}
    end.

-spec insert(binary(), term(), term()) -> {ok, nil} | {error, nil}.
insert(NameBin, Key, Value) ->
    try
        Name = binary_to_atom(NameBin),
        Tid = ets:whereis(Name),
        ets:insert(Tid, {Key, Value}),
        {ok, nil}
    catch
        error:badarg -> {error, nil}
    end.

-spec lookup(binary(), term()) -> {ok, term()} | {error, nil}.
lookup(NameBin, Key) ->
    try
        Name = binary_to_atom(NameBin),
        Tid = ets:whereis(Name),
        case ets:lookup(Tid, Key) of
            [{Key, Value}] -> {ok, Value};
            [] -> {error, nil}
        end
    catch
        error:badarg -> {error, nil}
    end.

-spec delete(binary(), term()) -> {ok, nil} | {error, nil}.
delete(NameBin, Key) ->
    try
        Name = binary_to_atom(NameBin),
        Tid = ets:whereis(Name),
        ets:delete(Tid, Key),
        {ok, nil}
    catch
        error:badarg -> {error, nil}
    end.

