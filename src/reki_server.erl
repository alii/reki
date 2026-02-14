-module(reki_server).
-behaviour(gen_server).

-export([start_link/2, start_child/4, whereis_server/1]).
-export([new_unique_atom/0, lookup/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% Start the registry gen_server, registered under ServerName.
-spec start_link(atom(), atom()) -> {ok, pid()} | {error, term()}.
start_link(ServerName, TableName) ->
    case gen_server:start_link({local, ServerName}, ?MODULE, TableName, []) of
        {ok, Pid} ->
            {ok, Pid};
        {error, {already_started, _}} ->
            {error, {init_failed, <<"already started">>}};
        {error, Reason} ->
            {error, {init_crashed, Reason}}
    end.

%% Call the registry to look up or start a child. Wraps gen_server:call
%% with exception handling so Gleam gets a clean Result back.
-spec start_child(atom(), term(), fun((term()) -> term()), integer()) -> term().
start_child(ServerName, Key, StartFn, Timeout) ->
    try gen_server:call(ServerName, {start_child, Key, StartFn}, Timeout)
    catch
        exit:{timeout, _} ->
            {error, init_timeout};
        exit:{noproc, _} ->
            {error, init_timeout};
        exit:Reason ->
            {error, {init_crashed, Reason}}
    end.

%% Look up the pid of the gen_server by registered name.
-spec whereis_server(atom()) -> {ok, pid()} | {error, nil}.
whereis_server(ServerName) ->
    case erlang:whereis(ServerName) of
        undefined -> {error, nil};
        Pid -> {ok, Pid}
    end.

%% Creates a unique atom for use as an ETS table name or server name.
%% WARNING: Atoms are never garbage collected by the BEAM. This function
%% must only be called a bounded number of times (e.g. at app startup).
-spec new_unique_atom() -> atom().
new_unique_atom() ->
    Suffix = integer_to_binary(erlang:unique_integer([positive])),
    Name = <<"reki$", Suffix/bits>>,
    binary_to_atom(Name).

%% Direct ETS lookup, callable from any process for the fast read path.
-spec lookup(atom(), term()) -> {some, term()} | none.
lookup(Table, Key) ->
    try
        case ets:lookup(Table, Key) of
            [{Key, Value}] -> {some, Value};
            [] -> none
        end
    catch
        error:badarg -> none
    end.

%% gen_server callbacks

init(TableName) ->
    process_flag(trap_exit, true),
    ets:new(TableName, [set, named_table, protected, {read_concurrency, true}]),
    {ok, #{table => TableName}}.

handle_call({start_child, Key, StartFn}, _From, #{table := Table} = State) ->
    Reply = case lookup(Table, Key) of
        {some, Subject} ->
            {ok, Subject};
        none ->
            try StartFn(Key) of
                {ok, {started, Pid, Subject}} ->
                    link(Pid),
                    ets:insert(Table, {Key, Subject}),
                    erlang:put(Pid, Key),
                    {ok, Subject};
                {error, Reason} ->
                    {error, Reason}
            catch
                _Class:Reason ->
                    {error, {init_crashed, Reason}}
            end
    end,
    {reply, Reply, State};

handle_call(which_children, _From, State) ->
    Children = [{undefined, Pid, worker, dynamic}
                || Pid <- erlang:get_keys(), is_pid(Pid)],
    {reply, Children, State};

handle_call(count_children, _From, State) ->
    Count = length([Pid || Pid <- erlang:get_keys(), is_pid(Pid)]),
    Reply = [{specs, 1}, {active, Count}, {supervisors, 0}, {workers, Count}],
    {reply, Reply, State};

handle_call(_Msg, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, _Reason}, #{table := Table} = State) ->
    case erlang:erase(Pid) of
        undefined -> ok;
        Key -> ets:delete(Table, Key)
    end,
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, kill)
    end, [Pid || Pid <- erlang:get_keys(), is_pid(Pid)]),
    ok.
