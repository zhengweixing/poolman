-module(poolman_SUITE).

-behavior(poolcow_worker).
-record(state, {arg}).
-include_lib("eunit/include/eunit.hrl").
%% API
-compile(export_all).
-compile(nowarn_export_all).

all() ->
    [
        ct_start_pool,
        ct_get_workers,
        ct_call_pool,
        ct_stop_pool,
        ct_start_group,
        ct_call_group,
        ct_stop_group
    ].


init_per_suite(Config) ->
    ok = application:ensure_started(gproc),
    ok = application:ensure_started(poolcow),
    Config.

end_per_suite(_Config) ->
    application:stop(gproc),
    application:stop(poolcow),
    ok.

ct_start_pool(_Config) ->
    PoolArgs = [
        {worker_module, ?MODULE},
        {size, 10},
        {auto_size, true},
        {pool_type, random} % random | hash | round_robin
    ],
    WorkerArgs = #{},
    {ok, Pid} = poolcow:start_pool(pool1, PoolArgs, WorkerArgs),
    ?assertEqual(true, is_pid(Pid)).

ct_call_pool(_Config) ->
    ?assertEqual({ok, <<"hello">>}, call(pool1)).

ct_get_workers(_Config) ->
    ?assertEqual(10, length(poolcow:workers(pool1))).

ct_stop_pool(_Config) ->
    ?assertEqual(ok, poolcow:stop_pool(pool1)),
    ?assertEqual([], poolcow:workers(pool1)).

ct_start_group(_Config) ->
    WorkerArgs = #{},
    WorkerName = test1111,
    ?assertEqual(ok, poolcow_group:ensure_started(group1, [{pool_type, random}])),
    {ok, Pid} = poolcow_group:add_worker(group1, WorkerName, ?MODULE, WorkerArgs),
    ?assertEqual(true, is_pid(Pid)).

ct_stop_group(_Config) ->
    ?assertEqual(ok, poolcow_group:stop_worker(test1111)),
    ?assertEqual({error, notfound}, poolcow_group:checkout(group1)),
    ?assertEqual(ok, poolcow:stop_pool(group1)),
    ?assertEqual([], poolcow:workers(group1)).

ct_call_group(_Config) ->
    {ok, #{id := Id}} = poolcow_group:checkout(group1),
    ?assertEqual({ok, <<"hello">>}, call(lists:concat([group1, Id]))).


call(Pool) ->
    poolcow:transaction(Pool,
        fun(Worker) ->
            gen_server:call(Worker, hello, infinity)
        end).

%% group callback
start_worker(GroupName, Id, _WorkerArgs) ->
    Pool = lists:concat([GroupName, Id]),
    PoolArgs = [
        {worker_module, ?MODULE},
        {size, 1},
        {auto_size, true},
        {pool_type, random} % random | hash | round_robin
    ],
    WorkerArgs = #{},
    poolcow:start_pool(Pool, PoolArgs, WorkerArgs).

%% group callback
stop_worker(GroupName, Id, _WorkerArgs) ->
    Pool = lists:concat([GroupName, Id]),
    poolcow:stop_pool(Pool).


init(WorkerArgs) ->
    {ok, #state{arg = WorkerArgs}}.

handle_call(hello, _From, #state{} = State) ->
    {ok, {ok, <<"hello">>}, State}.

handle_cast(_Req, #state{} = State) ->
    {ok, State}.

handle_info(_Req, #state{} = State) ->
    {ok, State}.

terminate(_Reason, #state{}) ->
    ok.
