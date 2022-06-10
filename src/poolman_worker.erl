-module(poolman_worker).
-behaviour(gen_server).
-export([start_link/4, start_link/5]).
%% API Function Exports
-export([]).
%% gen_server Function Exports
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([stop/1, do_safe_call/3]).

-record(state, {
    name :: {poolman:pool(), integer()},
    pool :: poolman:poo_name(),
    mod :: module(),
    child_state :: any()
}).

-type state() :: #state{}.

%%--------------------------------------------------------------------
%% Callback
%%--------------------------------------------------------------------
-callback init(Id :: integer(), Opts :: any()) ->
    {ok, State :: any()} |
    {error, Reason :: any()} |
    {stop, Reason :: any}.

-callback init(Opts :: any()) ->
    {ok, State :: any()} |
    {error, Reason :: any()} |
    {stop, Reason :: any}.

-callback init(Id :: integer(), Mod :: atom(), Opts :: any()) ->
    {ok, State :: any()} |
    {error, Reason :: any()} |
    {stop, Reason :: any}.

-callback handle_call(Req :: any(), From :: pid(), State :: any()) ->
    {reply, Reply :: any(), NewState :: any()} |
    {stop, Reason :: any(), NewState :: any()} |
    {ok, Reply :: any(), NewState :: any()}.

-callback handle_info(Info :: any(), State :: any()) ->
    {ok, NewState :: any()} |
    {stop, Reason :: any(), NewState :: any()} |
    {noreply, NewState :: any()}.

-callback handle_cast(Msg :: any(), State :: any()) ->
    {ok, NewState :: any()} |
    {stop, Reason :: any(), NewState :: any()} |
    {noreply, NewState :: any()}.

-callback terminate(Reason :: any(), State :: any()) ->
    ok.

-optional_callbacks([init/1, init/2, init/3]).

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
-spec stop(pid()) -> ok.
stop(Pid) ->
    gen_server:call(Pid, stop).

%% @doc Start a pool worker.
-spec start_link(Pool :: poolman:pool(), Id :: pos_integer(), Mod :: module(), WorkerArgs :: any()) ->
    gen:start_ret().
start_link(Pool, Id, Mod, WorkerArgs) ->
    gen_server:start_link(?MODULE, {Pool, {Pool, Id}, Id, Mod, WorkerArgs}, []).

%% @doc Start a pool worker,register WorkerName
-spec start_link(SerName :: atom(), Pool :: atom(), Id :: pos_integer(), Mod :: module(), WorkerArgs :: any()) ->
    gen:start_ret().
start_link(SerName, Pool, Id, Mod, WorkerArgs) ->
    gen_server:start_link({local, SerName}, ?MODULE, {Pool, {SerName, Id}, Id, Mod, WorkerArgs}, []).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------
-spec init({Pool :: poolman:pool(), Name :: any(), Id :: integer(), Mod :: module(), WorkerArgs :: any()}) ->
    {ok, #state{}} | {stop, any()}.
init({Pool, Name, Id, Mod, WorkerArgs}) ->
    {Mod1, Result} = do_init(Id, Mod, WorkerArgs),
    State = #state{pool = Pool, mod = Mod1, name = Name},
    case Result of
        {ok, ChildState, Timeout} ->
            true = gproc_pool:connect_worker(poolman:name(Pool), Name),
            {ok, State#state{child_state = ChildState}, Timeout};
        {ok, ChildState} ->
            true = gproc_pool:connect_worker(poolman:name(Pool), Name),
            {ok, State#state{child_state = ChildState}};
        {stop, Error} ->
            {stop, Error}
    end.

-spec handle_call(Req :: any(), From :: pid(), state()) ->
    {stop, Reason :: any(), Reply :: any(), state()} |
    {reply, Reply :: any(), state()}.
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(Req, From, #state{mod = Mod, child_state = ChildState} = State) ->
    case do_safe_call(Mod, handle_call, [Req, From, ChildState]) of
        {error, Reason} ->
            {reply, {error, Reason}, State};
        {ok, Reply, NewChildState} ->
            {reply, Reply, State#state{child_state = NewChildState}};
        {stop, Reason, Reply, NewChildState} ->
            {stop, Reason, Reply, State#state{child_state = NewChildState}};
        {stop, Reason, NewChildState} ->
            {stop, Reason, State#state{child_state = NewChildState}};
        {reply, Reply, NewChildState} ->
            {reply, Reply, State#state{child_state = NewChildState}};
        {reply, Reply, NewChildState, Timeout} ->
            {reply, Reply, State#state{child_state = NewChildState}, Timeout}
    end.

-spec handle_cast(Msg :: any(), state()) ->
    {noreply, state()} | {stop, Reason :: any(), state()}.
handle_cast(Msg, #state{mod = Mod, child_state = ChildState} = State) ->
    case do_safe_call(Mod, handle_cast, [Msg, ChildState]) of
        {ok, NewChildState} ->
            {noreply, State#state{child_state = NewChildState}};
        {error, Reason} ->
            logger:error("~p:handle_info, Info:~p, State:~p Reason:~p", [Mod, Msg, ChildState, Reason]),
            {noreply, State};
        {stop, Reason, NewChildState} ->
            {stop, Reason, State#state{child_state = NewChildState}};
        {noreply, NewChildState} ->
            {noreply, State#state{child_state = NewChildState}};
        {noreply, NewChildState, Timeout} ->
            {noreply, State#state{child_state = NewChildState}, Timeout}
    end.

-spec handle_info(Info :: any(), state()) ->
    {stop, Reason :: any(), state()} | {noreply, state()}.
handle_info(Info, #state{mod = Mod, child_state = ChildState} = State) ->
    case do_safe_call(Mod, handle_info, [Info, ChildState]) of
        {ok, NewChildState} ->
            {noreply, State#state{child_state = NewChildState}};
        {error, Reason} ->
            logger:error("~p:handle_info, Info:~p, State:~p Reason:~p", [Mod, Info, ChildState, Reason]),
            {noreply, State};
        {stop, Reason, NewChildState} ->
            {stop, Reason, State#state{child_state = NewChildState}};
        {noreply, NewChildState} ->
            {noreply, State#state{child_state = NewChildState}};
        {noreply, NewChildState, Timeout} ->
            {noreply, State#state{child_state = NewChildState}, Timeout}
    end.

-spec terminate(Reason :: any(), state()) -> ok.
terminate(Reason, #state{mod = Mod, pool = Pool, name = Name, child_state = ChildState}) ->
    gproc_pool:disconnect_worker(poolman:name(Pool), Name)
        andalso gproc_pool:remove_worker(poolman:name(Pool), Name)
        andalso Mod:terminate(Reason, ChildState),
    ok.

-spec code_change(OldVsn :: (term() | {down, term()}), State :: term(), Extra :: term()) ->
    {ok, NewState :: term()} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
-type child_state() ::
{ok, ChildState :: any(), Timeout :: integer()} |
{ok, ChildState :: any()} |
{stop, Reason :: any()}.
-spec do_init(
    Id :: integer(),
    {con, module()} | module(),
    WorkerArgs :: [poolman:worker_arg()]) ->
    {module(), Result :: child_state()}.

do_init(Id, {con, Mod}, WorkerArgs) ->
    Middleware = poolman_conn_worker,
    {Middleware, Middleware:init(Id, Mod, WorkerArgs)};
do_init(Id, Mod, WorkerArgs) ->
    Result =
        case erlang:function_exported(Mod, init, 2) of
            true ->
                Mod:init(Id, WorkerArgs);
            false ->
                Mod:init(WorkerArgs)
        end,
    {Mod, Result}.


-spec do_safe_call(Mod :: module(), Fun :: atom(), Args :: list()) ->
    {error, any()} | any().
do_safe_call(Mod, Fun, Args) ->
    try
        apply(Mod, Fun, Args)
    catch
        _:Reason ->
            {error, {Mod, Fun, Reason}}
    end.
