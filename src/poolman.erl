-module(poolman).

-export([
    pool_spec/3,
    start_pool/3,
    stop_pool/1,
    checkout/1,
    checkout/2,
    transaction/2,
    transaction/3,
    name/1,
    workers/1,
    info/1
]).

-type pool() :: any().
-type pool_type() :: random | hash | round_robin | direct | claim.
-type worker_arg() :: list() | map().
-type pool_option() :: {worker_module, Mod :: module()} |
                       {worker_module, {con, module()}} |
                       {size, integer()} |
                       {auto_size, boolean()} |
                       {pool_type, pool_type()}.
-type worker() :: {{Name :: pool(), Idx :: integer()}, Pid :: pid()}.
-type info() :: {parent, pid()} | {pool_type, pool_type()}.
-export_type([pool/0, pool_type/0, info/0, worker/0]).

-spec pool_spec(Pool :: pool(), PoolArgs :: [pool_option()], WorkerArgs :: worker_arg()) ->
    supervisor:child_spec().
pool_spec(Pool, PoolArgs, WorkerArgs) ->
    #{
        id => child_id(Pool),
        start => {poolman_pool_sup, start_link, [Pool, PoolArgs, WorkerArgs]},
        restart => transient,
        shutdown => 5000,
        type => supervisor,
        modules => [poolman_pool_sup]
    }.

%% @doc Start the pool supervised by poolman_sup
-spec start_pool(Pool :: pool(), PoolArgs :: [pool_option()], WorkerArgs :: worker_arg()) ->
    supervisor:startchild_ret().
start_pool(Pool, PoolArgs, WorkerArgs) ->
    Spec = pool_spec(Pool, PoolArgs, WorkerArgs),
    supervisor:start_child(poolman_sup, Spec).

%% @doc Stop a pool. start by poolman_sup
-spec stop_pool(Pool :: pool()) -> ok | {error, term()}.
stop_pool(Pool) ->
    ChildId = child_id(Pool),
    poolman_pool:stop(Pool, ChildId).

-spec checkout(Pool :: pool()) -> pid() | false.
checkout(Pool) ->
    gproc_pool:pick_worker(name(Pool)).

-spec checkout(Pool :: pool(), any()) -> pid() | false.
checkout(Pool, Key) ->
    gproc_pool:pick_worker(name(Pool), Key).

-spec transaction(Pool :: pool(), fun((Worker :: pid()) -> any())) -> {error, notfound} | any().
transaction(Pool, Fun) ->
    Worker = checkout(Pool),
    case is_pid(Worker) andalso is_process_alive(Worker) of
        true ->
            Fun(Worker);
        false ->
            {error, notfound}
    end.

-spec transaction(Pool :: pool(), Key :: any(), fun((Worker :: pid()) -> any())) -> {error, notfound} | any().
transaction(Pool, Key, Fun) ->
    Worker = checkout(Pool, Key),
    case is_pid(Worker) andalso is_process_alive(Worker) of
        true ->
            Fun(Worker);
        false ->
            {error, notfound}
    end.

%% @doc Pool workers
-spec workers(Pool :: pool()) -> [worker()].
workers(Pool) ->
    gproc_pool:active_workers(name(Pool)).


-spec info(Pool :: poolman:pool()) -> [info()] | undefined.
info(Pool) ->
    poolman_pool:info(Pool).

%% @doc poolman name
-spec name(Pool :: atom()) -> {module(), atom()}.
name(Pool) -> {?MODULE, Pool}.

-spec child_id(Pool :: atom()) ->
    {child_id, atom()}.
child_id(Pool) -> {child_id, Pool}.
