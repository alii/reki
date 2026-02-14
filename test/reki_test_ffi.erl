-module(reki_test_ffi).
-export([which_children/1, count_children/1]).

%% Calls supervisor:which_children/1 and extracts just the pids.
which_children(Pid) ->
    [ChildPid || {_Id, ChildPid, _Type, _Modules} <- supervisor:which_children(Pid)].

%% Calls supervisor:count_children/1 and returns the active count.
count_children(Pid) ->
    proplists:get_value(active, supervisor:count_children(Pid)).
