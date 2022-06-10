-module(poolman_sup).

-behaviour(supervisor).

-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% @doc Start supervisor.
-spec(start_link() -> {ok, pid()} | {error, term()}).
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%--------------------------------------------------------------------
%% Supervisor callbacks
%%--------------------------------------------------------------------
-spec init([]) -> {ok,
    {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}}
| ignore.
init([]) ->
    {ok, {{one_for_one, 10, 100}, []}}.

