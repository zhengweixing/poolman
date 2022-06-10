-module(poolman_group).

-behavior(poolman_worker).
%% API
-export([
    start/2,
    ensure_started/2,
    add_worker/3,
    add_worker/4,
    stop_worker/1,
    checkout/1,
    is_worker_alive/1
]).
-export([init/2, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-record(state, {group, id, worker_pid, worker_args, mod}).
-define(TIMEOUT, 1000).
-type state() :: #state{}.

% @doc pick_worker do not anything, only pick pool name,
-type info() :: #{id := integer(), worker_pid := undefined | pid(), worker_args := any()}.
-spec checkout(GroupName :: poolman:pool() | pid()) ->
    {ok, Info :: info()} | {error, notfound | any()}.
checkout(WorkerPid) when is_pid(WorkerPid) ->
    gen_server:call(WorkerPid, pick, ?TIMEOUT);
checkout(GroupName) ->
    poolman:transaction(GroupName,
        fun(Pid) ->
            checkout(Pid)
        end).

%% @doc maksure the auto pool start
-type opt() :: {pool_type, poolman:pool_type()}.
-spec start(GroupName :: poolman:pool(), [opt()]) ->
    {ok, pid()} | {error, Reason :: any()}.
start(GroupName, Opts) ->
    PoolArgs = [
        {worker_module, ?MODULE},
        {auto_size, true}
    ] ++ Opts,
    InitArgs = #{name => GroupName},
    poolman:start_pool(GroupName, PoolArgs, InitArgs).


-spec ensure_started(GroupName :: poolman:pool(), [opt()]) -> ok.
ensure_started(GroupName, Opts) ->
    case poolman:info(GroupName) of
        undefined ->
            case start(GroupName, Opts) of
                {ok, _} ->
                    ok;
                {error, Reason} ->
                    throw({error, Reason})
            end;
        _Info ->
            ok
    end.


-spec add_worker(GroupName :: poolman:pool(), ModOrPid :: module() | pid(), WorkerArgs :: any()) ->
    {ok, pid()} | {error, any()}.
add_worker(GroupName, ModOrPid, WorkerArgs) ->
    poolman_pool:add_worker(GroupName, ModOrPid, WorkerArgs).

-spec add_worker(
    GroupName :: poolman:pool(),
    WorkerName :: poolman:pool(),
    ModOrPid :: module() | pid(),
    WorkerArgs :: any()) -> {ok, pid()} | {error, any()}.
add_worker(GroupName, WorkerName, ModOrPid, WorkerArgs) ->
    poolman_pool:add_worker(GroupName, WorkerName, ModOrPid, WorkerArgs).


-spec is_worker_alive(WorkerName :: atom()) -> pid() | undefined.
is_worker_alive(WorkerName) ->
    case WorkerName =/= undefined andalso whereis(WorkerName) of
        Pid when is_pid(Pid) -> Pid;
        _ -> undefined
    end.


%% @doc only for worker name was registered
-spec stop_worker(WorkerName :: atom()) -> ok | {error, any()}.
stop_worker(WorkerName) ->
    case is_worker_alive(WorkerName) of
        undefined ->
            ok;
        Pid ->
            poolman_pool:stop_worker(Pid)
    end.

%%%===================================================================
%%% poolman callbacks
%%%===================================================================
-spec init(Id :: integer(), list()) ->
    {ok, state()} | {stop, Reason :: any()}.
init(Id, [#{name := GroupName}, ModOrPid, WorkerArgs]) ->
    State = #state{group = GroupName, id = Id, worker_args = WorkerArgs},
    case ModOrPid of
        WorkerPid when is_pid(ModOrPid) ->
            erlang:monitor(process, WorkerPid),
            {ok, State#state{worker_pid = WorkerPid}};
        Mod when is_atom(Mod) ->
            case do_start_worker(State#state{mod = Mod}) of
                {ok, NewState} ->
                    {ok, NewState};
                {error, Reason} ->
                    {stop, Reason}
            end
    end.

-spec handle_call(pick, From :: pid(), state()) ->
    {reply, Reply :: any(), state()}.
handle_call(pick, _From, #state{
    id = Id,
    worker_pid = Pid,
    worker_args = WorkerArgs
} = State) ->
    Reply = #{
        id => Id,
        worker_pid => Pid,
        worker_args => WorkerArgs
    },
    {reply, {ok, Reply}, State}.

-spec handle_cast(Request :: any(), state()) ->
    {noreply, state()}.
handle_cast(_Request, State) ->
    {noreply, State}.

-spec handle_info(Info :: any(), state()) ->
    {stop, Reason :: normal, state()} | {noreply, state()}.
handle_info({'DOWN', _Ref, process, Pid, Reason}, #state{
    group = GroupName,
    id = Id,
    worker_pid = Pid
} = State) ->
    logger:info("The worker pool[Group:~p, Id:~p] down, Reason:~p~n",
        [GroupName, Id, Reason]),
    {stop, normal, State#state{worker_pid = undefined}};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(Reason :: any(), state()) -> ok.
terminate(Reason, #state{
    mod = Mod,
    group = GroupName,
    id = Id,
    worker_args = WorkerArgs
}) ->
    case Mod:stop_worker(GroupName, Id, WorkerArgs) of
        ok -> ok;
        {error, Why} ->
            logger:error("The pool[Group:~p, Id:~p] is stop, Reason:~p, but fun ~p:stop_worker/2 return ~p",
                [GroupName, Id, Reason, Mod, Why])
    end,
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%% start child pool
do_start_worker(#state{
    group = GroupName,
    id = Id,
    mod = Mod,
    worker_args = WorkerArgs
} = State) ->
    case Mod:start_worker(GroupName, Id, WorkerArgs) of
        {ok, WorkerPid} when is_pid(WorkerPid) ->
            erlang:monitor(process, WorkerPid),
            {ok, State#state{worker_pid = WorkerPid}};
        {ok, NewWorkerArgs} ->
            {ok, State#state{worker_args = NewWorkerArgs}};
        {ok, WorkerPid, NewWorkerArgs} ->
            erlang:monitor(process, WorkerPid),
            {ok, State#state{worker_pid = WorkerPid, worker_args = NewWorkerArgs}};
        {error, Reason} ->
            {error, Reason}
    end.

