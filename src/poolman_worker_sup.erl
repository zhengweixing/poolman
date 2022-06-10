-module(poolman_worker_sup).
-behaviour(supervisor).
-export([start_link/3, start_child/4, start_child/5, delete_child/2]).
-export([init/1]).

-spec start_child(
    Pool :: poolcow:pool(),
    Id :: integer(),
    PoolArgs :: [poolcow:pool_option()],
    WorkerArgs :: poolcow:worker_arg()) ->
    supervisor:sup_ref().
start_child(Pool, Id, PoolArgs, WorkerArgs) ->
    Mod = proplists:get_value(worker_module, PoolArgs),
    supervisor:start_child(get_server(Pool), [Pool, Id, Mod, WorkerArgs]).

-spec start_child(
    Pool :: poolcow:pool(),
    WorkerName :: any(),
    Id :: integer(),
    PoolArgs :: [poolcow:pool_option()],
    WorkerArgs :: poolcow:worker_arg()) ->
    supervisor:sup_ref().
start_child(Pool, WorkerName, Id, PoolArgs, WorkerArgs) ->
    Mod = proplists:get_value(worker_module, PoolArgs),
    supervisor:start_child(get_server(Pool), [WorkerName, Pool, Id, Mod, WorkerArgs]).


-spec start_link(Pool :: poolcow:pool(), PoolArgs :: [poolcow:pool_option()], WorkerArgs :: poolcow:worker_arg()) ->
    supervisor:sup_ref().
start_link(Pool, PoolArgs, WorkerArgs) ->
    Mod = proplists:get_value(worker_module, PoolArgs),
    Size = poolcow_pool:get_size(PoolArgs),
    case supervisor:start_link({local, get_server(Pool)}, ?MODULE, []) of
        {ok, Sup} ->
            [{ok, _} = supervisor:start_child(Sup, [Pool, Id, Mod, WorkerArgs]) || Id <- lists:seq(1, Size)],
            {ok, Sup};
        Other ->
            Other
    end.

-spec delete_child(Pool :: poolcow:pool(), Id :: integer()) ->
    {error, any()} | ok.
delete_child(Pool, Id) ->
    case supervisor:terminate_child(get_server(Pool), {worker, Id}) of
        ok ->
            supervisor:delete_child(get_server(Pool), {worker, Id});
        {error, Reason} ->
            {error, Reason}
    end.

-spec init(list()) ->
    {ok, {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}} |
    ignore.
init([]) ->
    Worker = #{
        id => worker,
        start => {poolcow_worker, start_link, []},
        restart => transient,
        shutdown => 5000,
        type => worker,
        modules => [poolcow_worker]
    },
    {ok, {{simple_one_for_one, 10, 60}, [Worker]}}.


-spec get_server(binary() | list() | atom()) -> atom().
get_server(Name) when is_binary(Name) ->
    binary_to_atom(<<Name/binary, "_worker_sup">>);
get_server(Name) when is_list(Name) ->
    list_to_atom(Name ++ "_worker_sup");
get_server(Name) when is_atom(Name) ->
    list_to_atom(lists:concat([Name, '_worker_sup'])).
