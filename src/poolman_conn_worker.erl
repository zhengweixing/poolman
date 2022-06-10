-module(poolman_conn_worker).
-behavior(poolman_worker).
-export([client/1, is_connected/1]).
-export([init/3, handle_call/3, handle_info/2, handle_cast/2, terminate/2]).
-record(state, {
    id :: integer(),
    client :: pid() | undefined,
    mod :: module(),
    opts :: proplists:proplist()
}).
-define(SLEEP, 30).
-type state() :: #state{}.
%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------
-callback connect(Opts :: any()) ->
    {ok, Client :: pid()} |
    {ok, Client :: pid()} |
    {error, Reason :: any()}.


%% @doc Get client/connection.
-spec client(pid()) -> {ok, Client :: pid()} | {error, Reason :: term()}.
client(Pid) ->
    gen_server:call(Pid, client, infinity).

%% @doc Is client connected?
-spec is_connected(pid()) -> boolean().
is_connected(Pid) ->
    gen_server:call(Pid, is_connected, infinity).

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

-spec init(Id :: integer(), Mod :: module(), Opts :: list()) ->
    {ok, state()}.
init(Id, Mod, Opts) ->
    process_flag(trap_exit, true),
    State = #state{
        id = Id,
        mod = Mod,
        opts = Opts
    },
    case connect(State) of
        {ok, NewState} ->
            {ok, NewState};
        {error, Reason, NewState} ->
            logger:error("~p:connect/1 error, opts:~p error, ~p", [Mod, Opts, Reason]),
            {ok, reconnect(NewState)}
    end.

-spec handle_call(Msg :: any(), From :: pid(), state()) ->
    {reply, Reply :: any(), state()}.
handle_call(is_connected, _From, State = #state{client = Client}) ->
    IsAlive = is_pid(Client) andalso is_process_alive(Client),
    {reply, IsAlive, State};

handle_call(client, _From, State = #state{client = Client}) ->
    case is_pid(Client) andalso is_process_alive(Client) of
        false ->
            {reply, {error, disconnected}, State};
        true ->
            {reply, {ok, Client}, State}
    end;

handle_call(Req, _From, #state{client = Client} = State) ->
    case is_pid(Client) andalso is_process_alive(Client) of
        false ->
            {reply, {error, disconnected}, State};
        true ->
            Reply = gen_server:call(Client, Req, infinity),
            {reply, Reply, State}
    end.


-spec handle_info(Info :: any(), state()) ->
    {noreply, state()}.
handle_info({'EXIT', Pid, Reason}, State) ->
    case State#state.client == Pid of
        true ->
            handle_info(reconnect, State);
        false ->
            logger:debug("~p received unexpected exit:~0p from ~p", [?MODULE, Reason, Pid]),
            {noreply, State}
    end;

handle_info(reconnect, State = #state{opts = Opts}) ->
    case connect(State) of
        {ok, NewState} ->
            {noreply, NewState};
        {error, Reason, NewState} ->
            logger:error("~p:connect/1 error, opts:~p error, ~p", [State#state.mod, Opts, Reason]),
            {noreply, reconnect(NewState)}
    end;

handle_info(Info, #state{client = Client} = State) ->
    case is_pid(Client) andalso is_process_alive(Client) of
        false ->
            {noreply, State#state{client = undefined}};
        true ->
            Client ! Info,
            {noreply, State}
    end.


-spec handle_cast(Msg :: any(), state()) ->
    {noreply, state()}.
handle_cast(Msg, #state{client = Client} = State) ->
    case is_pid(Client) andalso is_process_alive(Client) of
        false ->
            {noreply, State#state{client = undefined}};
        true ->
            gen_server:cast(Client, Msg),
            {noreply, State}
    end.


-spec terminate(Reason :: any(), state()) -> ok.
terminate(Reason, #state{client = Client}) ->
    case is_pid(Client) andalso is_process_alive(Client) of
        true ->
            erlang:unlink(Client),
            exit(Client, Reason);
        false ->
            ok
    end,
    ok.

%%--------------------------------------------------------------------
%% Internal Functions
%%--------------------------------------------------------------------
-spec reconnect(state()) -> NewState :: state().
reconnect(#state{opts = Opts} = State) ->
    reconnect(get_val(auto_reconnect, Opts, ?SLEEP), State).
reconnect(Secs, State) ->
    erlang:send_after(timer:seconds(Secs), self(), reconnect),
    State#state{client = undefined}.

-spec connect(state()) ->
    {ok, state()} | {error, Reason :: any(), state()}.
connect(#state{id = Id, mod = Mod, opts = Opts} = State) ->
    try
        Result =
            case erlang:function_exported(Mod, connect, 2) of
                true ->
                    Mod:connect(Id, Opts);
                false ->
                    Mod:connect(Opts)
            end,
        case Result of
            {ok, Pid} ->
                erlang:link(Pid),
                {ok, State#state{
                    client = Pid
                }};
            {error, Error} ->
                {error, Error, State}
        end
    catch
        _C:Reason ->
            {error, Reason, State}
    end.


-spec get_val(Key :: atom(), Opts :: list() | map()) ->
    undefined | any().
get_val(Key, Opts) when is_list(Opts) ->
    proplists:get_value(Key, Opts);
get_val(Key, Map) when is_map(Map) ->
    maps:get(Key, Map, undefined).

-spec get_val(Key :: any(), Map :: list() | map(), Def :: any()) ->
    undefined | any().
get_val(Key, Map, Def) ->
    case get_val(Key, Map) of
        undefined -> Def;
        Value -> Value
    end.
