# poolman

pool manager

## Usage

### Behaviour

```erlang
-type pool() :: any().
-type pool_type() :: random | hash | round_robin | direct | claim.
-type worker_arg() :: list() | map().
-type pool_option() :: {worker_module, Mod :: module()} |
                       {worker_module, {con, module()}} |
                       {size, integer()} |
                       {auto_size, boolean()} |
                       {pool_type, pool_type()}.

-spec start_pool(Pool :: pool(), PoolArgs :: [pool_option()], WorkerArgs :: worker_arg()) ->
    supervisor:startchild_ret().

%% @doc start pool
poolman:start_pool(Name, PoolArgs, WorkerArgs).

%% @doc get workers
poolman:workers(Pool).

%% @doc get pool info
poolman:info(Pool).

%% @doc call pool
poolman:transaction(Pool, fun(Worker) -> gen_server:call(Worker, hello)  end).

```


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

## Connection Pool
it is designed to pool connection/clients to server or database.

the `worker_module` must be `{con, module()}`
```erlang
-module(example_worker).
-behaviour(poolman_worker).

-export([connect/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {conn}).

connect(Args) ->
    gen_server:start_link(?MODULE, Args, []).

init(Args) ->
    Hostname = proplists:get_value(hostname, Args),
    Database = proplists:get_value(database, Args),
    Username = proplists:get_value(username, Args),
    Password = proplists:get_value(password, Args),
    {ok, Conn} = epgsql:connect(Hostname, Username, Password, [
        {database, Database}
    ]),
    {ok, #state{conn=Conn}}.

handle_call({squery, Sql}, _From, #state{conn=Conn}=State) ->
    {reply, epgsql:squery(Conn, Sql), State};
handle_call({equery, Stmt, Params}, _From, #state{conn=Conn}=State) ->
    {reply, epgsql:equery(Conn, Stmt, Params), State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{conn=Conn}) ->
    ok = epgsql:close(Conn),
    ok.
```
