-module(poolman_pool).
-behaviour(gen_server).
%% API Function Exports
-export([start_link/4]).
-export([add_worker/3, add_worker/4, stop_worker/1, stop_worker/2, info/1, stop/2, get_size/1]).
%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-import(proplists, [get_value/3]).
-record(state, {parent, name, pool_args, worker_args}).

-type state() :: #state{}.

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
-spec start_link(Parent :: pid(), Pool :: poolcow:pool(), PoolArgs :: list(), WorkerArgs :: any()) ->
    gen:start_ret().
start_link(Parent, Pool, PoolArgs, WorkerArgs) ->
    gen_server:start_link({local, get_server(Pool)}, ?MODULE, [Parent, Pool, PoolArgs, WorkerArgs], []).


%% @doc add worker to pool, the auto_size must be true
-spec add_worker(Pool :: poolcow:pool(), Mod :: module() | pid(), WorkerArgs :: any()) -> {ok, pid()} | {error, any()}.
add_worker(Pool, ModOrPid, WorkerArgs) ->
    gen_server:call(get_server(Pool), {add_worker, undefined, ModOrPid, WorkerArgs}, 5000).

%% @doc add worker to pool, the auto_size must be true
-spec add_worker(Pool :: poolcow:pool(), WorkerName :: atom(), ModOrPid :: module() | pid(), WorkerArgs :: any()) ->
    {ok, pid()} | {error, any()}.
add_worker(Pool, WorkerName, ModOrPid, WorkerArgs) ->
    gen_server:call(get_server(Pool), {add_worker, WorkerName, ModOrPid, WorkerArgs}, 5000).


%% @doc call for poolcow_worker
-spec stop_worker(Pool :: poolcow:pool(), Id :: integer()) -> ok.
stop_worker(Pool, Id) ->
    case get_worker_by_id(Pool, Id) of
        undefined ->
            ok;
        Pid ->
            stop_worker(Pid)
    end.

-spec stop_worker(Pid :: pid()) -> ok.
stop_worker(Pid) ->
    poolcow_worker:stop(Pid).


-spec stop(Pool :: poolcow:pool(), ChildId :: any()) -> ok.
stop(Pool, ChildId) ->
    Info = info(Pool),
    [stop_worker(Pid) || {_, Pid} <- poolcow:workers(Pool)],
    gproc_pool:force_delete(poolcow:name(Pool)),
    {parent, Sup} = lists:keyfind(parent, 1, Info),
    case supervisor:terminate_child(Sup, ChildId) of
        ok ->
            supervisor:delete_child(Sup, ChildId);
        {error, Reason} ->
            {error, Reason}
    end.


-spec info(Pool :: poolcow:pool()) -> [poolcow:info()] | undefined.
info(Pool) ->
    case is_alive(Pool) of
        undefined ->
            undefined;
        Pid ->
            gen_server:call(Pid, info)
    end.

-spec is_alive(Pool :: poolcow:pool()) -> pid() | undefined.
is_alive(Pool) ->
    Pid = whereis(get_server(Pool)),
    case is_pid(Pid) andalso is_process_alive(Pid) of
        true ->
            Pid;
        false ->
            undefined
    end.

-spec get_size(poolcow:pool_option()) -> integer().
get_size(PoolArgs) ->
    proplists:get_value(size, PoolArgs, 0).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------
-spec init(list()) -> {ok, state()}.
init([Parent, Pool, PoolArgs, WorkerArgs]) ->
    PoolSize = get_size(PoolArgs),
    PoolType = get_value(pool_type, PoolArgs, random),
    AutoSize = get_value(auto_size, PoolArgs, false),
    ok = ensure_pool(poolcow:name(Pool), PoolType, [{size, PoolSize}, {auto_size, AutoSize}]),
    ok = lists:foreach(
        fun(I) ->
            Name = {Pool, I},
            ensure_pool_worker(poolcow:name(Pool), Name, I)
        end, lists:seq(1, PoolSize)),
    {ok, #state{parent = Parent, name = Pool, pool_args = PoolArgs, worker_args = WorkerArgs}}.

-spec handle_call(Request :: any(), From :: pid(), state()) ->
    {reply, Reply :: any(), state()}.
handle_call({add_worker, WorkerName, ModOrPid, WorkerArgs}, _From, #state{
    name = Pool,
    pool_args = PoolArgs,
    worker_args = InitArgs
} = State) ->
    Index = get_index(Pool),
    Args = [InitArgs, ModOrPid, WorkerArgs],
    Result =
        case WorkerName of
            undefined ->
                Name = {Pool, Index},
                ensure_pool_worker(poolcow:name(Pool), Name, Index),
                poolcow_worker_sup:start_child(Pool, Index, PoolArgs, Args);
            _ ->
                Name = {WorkerName, Index},
                ensure_pool_worker(poolcow:name(Pool), Name, Index),
                poolcow_worker_sup:start_child(Pool, WorkerName, Index, PoolArgs, Args)
        end,
    case Result of
        {ok, Pid} ->
            {reply, {ok, Pid}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(info, _From, State = #state{parent = Parent, pool_args = PoolArgs, worker_args = WorkerArgs}) ->
    PoolType = get_value(pool_type, PoolArgs, random),
    Info = [
        {parent, Parent},
        {pool_type, PoolType},
        {worker_args, WorkerArgs}
    ],
    {reply, Info, State};

handle_call(Req, _From, State) ->
    {reply, {unexpected_message, Req}, State}.

-spec handle_cast(Msg :: any(), state()) ->
    {noreply, state()}.
handle_cast(Msg, State) ->
    logger:error("[Pool] unexpected_message: ~p", [Msg]),
    {noreply, State}.

-spec handle_info(Info :: any(), state()) ->
    {noreply, state()}.
handle_info(Info, State) ->
    logger:error("[Pool] unexpected_info: ~p", [Info]),
    {noreply, State}.

-spec terminate(Reason :: any(), state()) -> ok.
terminate(_Reason, #state{}) ->
    ok.

-spec code_change(OldVsn :: (term() | {down, term()}), State :: term(), Extra :: term()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec ensure_pool(Pool :: poolcow:pool(), Type :: poolcow:pool_type(), Opts :: poolcow:pool_option()) ->
    exists | ok.
ensure_pool(Pool, Type, Opts) ->
    try
        gproc_pool:force_delete(Pool),
        gproc_pool:new(Pool, Type, Opts)
    catch
        error:exists -> exists
    end.

-spec ensure_pool_worker(Pool :: poolcow:pool(), Name :: any(), Slot :: integer()) ->
    ok.
ensure_pool_worker(Pool, Name, Slot) ->
    try gproc_pool:add_worker(Pool, Name, Slot)
    catch
        error:exists -> ok
    end.

-spec get_server(Name :: list() | binary() | atom()) -> atom().
get_server(Name) when is_binary(Name) ->
    binary_to_atom(<<Name/binary, "">>);
get_server(Name) when is_list(Name) ->
    list_to_atom(Name ++ "");
get_server(Name) when is_atom(Name) ->
    list_to_atom(lists:concat([Name, ''])).

-spec get_index(Pool :: poolcow:pool()) -> integer().
get_index(Pool) ->
    Workers = poolcow:workers(Pool),
    L = [I || {{_, I}, _Pid} <- Workers],
    get_index(L, 1).

-spec get_index(L :: list(), I :: integer()) ->
    integer().
get_index(L, I) ->
    case lists:member(I, L) of
        true ->
            get_index(L, I + 1);
        false ->
            I
    end.

-spec get_worker_by_id(Pool :: poolcow:pool(), Id :: integer()) ->
    undefined | pid().
get_worker_by_id(Pool, Id) ->
    Workers = poolcow:workers(Pool),
    find_worker(Id, Workers).

-spec find_worker(Id :: integer(), [poolcow:worker()]) -> undefined | pid().
find_worker(_, []) -> undefined;
find_worker(Id, [{{_, Id}, Pid} | _]) -> Pid;
find_worker(Id, [_ | Workers]) ->
    find_worker(Id, Workers).
