# poolman

pool manager

## Example
example_worker.erl
```erlang
-module(example_worker).
-behaviour(poolman_worker).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-record(state, {}).

init(_WorkerArgs) ->
    {ok, #state{ }}.

handle_call(hello, _From, #state{} = State) ->
    {ok, {ok, <<"hello">>}, State}.

handle_cast(_Req, #state{} = State) ->
    {ok, State}.

handle_info(_Req, #state{} = State) ->
    {ok, State}.

terminate(_Reason, #state{}) ->
    ok.
```

start pool
```erlang
PoolArgs = [
    {worker_module, example_worker},
    {size, 1},
    {auto_size, true},
    {pool_type, random} % random | hash | round_robin
],
WorkerArgs = #{},
poolman:start_pool(test, PoolArgs, WorkerArgs).

%% @doc get workers
poolman:workers(test).

%% @doc get pool info
poolman:info(test).

%% @doc call pool
poolman:transaction(test, fun(Worker) -> gen_server:call(Worker, hello)  end).
```

## Connection Pool
it is designed to pool connection/clients to server or database.

the `worker_module` must be `{con, module()}`
```erlang
-module(pg_worker).
-behaviour(poolman_worker).

-export([connect/1]).

connect(Args) ->
    Hostname = proplists:get_value(hostname, Args),
    Database = proplists:get_value(database, Args),
    Username = proplists:get_value(username, Args),
    Password = proplists:get_value(password, Args),
    epgsql:connect(Hostname, Username, Password, [
        {database, Database}
    ]).
```
start pool
```erlang
PoolArgs = [
    {worker_module, {con, pg_worker}},
    {size, 1},
    {auto_size, true},
    {pool_type, random} % random | hash | round_robin
],
WorkerArgs = [
    {hostname, "127.0.0.1"},
    {database, "db"},
    {username, "admin"},
    {password, "123456"}
],
poolman:start_pool(pg, PoolArgs, WorkerArgs).

%% @doc call pool
poolman:transaction(pg, fun(Conn) -> epgsql:squery(Conn, Sql)  end).
```