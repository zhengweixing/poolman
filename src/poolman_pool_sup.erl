-module(poolman_pool_sup).

-behaviour(supervisor).

%% API
-export([start_link/3]).

%% Supervisor callbacks
-export([init/1]).

-spec start_link(Pool :: poolcow:pool(), PoolArgs :: [poolcow:pool_option()], WorkerArgs :: poolcow:worker_arg()) ->
    supervisor:startlink_ret().
start_link(Pool, PoolArgs, WorkerArgs) ->
    supervisor:start_link(?MODULE, [self(), Pool, PoolArgs, WorkerArgs]).


-spec init(list()) -> {ok, {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}} | ignore.
init([Parent, Pool, PoolArgs, WorkerArgs]) ->
    Children = [
        {poolcow_pool, {poolcow_pool, start_link, [Parent, Pool, PoolArgs, WorkerArgs]},
            transient, infinity, worker, [poolcow_pool]},
        {poolcow_worker_sup, {poolcow_worker_sup, start_link, [Pool, PoolArgs, WorkerArgs]},
            transient, infinity, supervisor, [poolcow_worker_sup]}
    ],
    {ok, {{one_for_all, 10, 100}, Children}}.
