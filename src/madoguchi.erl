-module(madoguchi).
-moduledoc """
An MCP server framework for the BEAM. Define tools as modules implementing
`m:madoguchi_tool`, collect them in a server definition, and serve them over the
Model Context Protocol (Streamable HTTP, JSON-RPC 2.0, protocol `2025-06-18`).

```erlang
Server = #{name => ~"weather", version => ~"1.0.0", tools => [weather_tool]},
{ok, _} = madoguchi:start_http(Server, #{port => 8080}).
```

`dispatch/2` is the transport-agnostic seam: the bundled Cowboy handler, a Nova
controller, or a test all call it with a decoded or raw JSON-RPC message.
""".

-export([dispatch/2, start_http/1, start_http/2, stop_http/1]).

-export_type([server/0, http_opts/0]).

-type server() :: #{
    name := binary(),
    version := binary(),
    tools := [module()],
    resources => [module()],
    prompts => [module()]
}.

-type http_opts() :: #{
    port => inet:port_number(),
    ip => inet:ip_address(),
    path => iodata(),
    ref => ranch:ref(),
    allowed_origins => same_host | any | [binary()]
}.

-doc """
Route a JSON-RPC message against a server definition. Accepts a raw JSON binary
(decoded here) or an already-decoded map. Returns `{reply, Response}` to send
back, or `noreply` for a notification.
""".
-spec dispatch(binary() | map(), server()) -> {reply, map()} | noreply.
dispatch(Body, Server) when is_binary(Body) ->
    try json:decode(Body) of
        Msg when is_map(Msg) -> madoguchi_dispatch:handle(Msg, Server);
        _ -> {reply, error_response(null, -32600, ~"Invalid Request")}
    catch
        _:_ -> {reply, error_response(null, -32700, ~"Parse error")}
    end;
dispatch(Msg, Server) when is_map(Msg) ->
    madoguchi_dispatch:handle(Msg, Server).

-doc "Start a Cowboy listener serving the MCP endpoint with default options.".
-spec start_http(server()) -> {ok, pid()} | {error, term()}.
start_http(Server) ->
    start_http(Server, #{}).

-doc """
Start a Cowboy listener serving the MCP endpoint. Options:

- `port` (default `8080`)
- `ip` (default `{127, 0, 0, 1}`) - the bind address. Defaults to loopback so a
  local MCP server is not exposed on every interface; set `{0, 0, 0, 0}` to bind
  all interfaces.
- `path` (default `"/mcp"`)
- `ref` (listener name, default `madoguchi_http`)
- `allowed_origins` (default `same_host`) - DNS-rebinding protection for the
  `Origin` header; `same_host`, `any`, or an explicit list of allowed origins.
""".
-spec start_http(server(), http_opts()) -> {ok, pid()} | {error, term()}.
start_http(Server, Opts) ->
    Port = maps:get(port, Opts, 8080),
    Ip = maps:get(ip, Opts, {127, 0, 0, 1}),
    Path = maps:get(path, Opts, "/mcp"),
    Ref = maps:get(ref, Opts, madoguchi_http),
    Dispatch = cowboy_router:compile([{'_', [{Path, madoguchi_http_handler, {Server, Opts}}]}]),
    cowboy:start_clear(Ref, [{port, Port}, {ip, Ip}], #{env => #{dispatch => Dispatch}}).

-doc "Stop a listener started by `start_http/1,2`.".
-spec stop_http(ranch:ref()) -> ok | {error, not_found}.
stop_http(Ref) ->
    cowboy:stop_listener(Ref).

error_response(Id, Code, Message) ->
    #{jsonrpc => ~"2.0", id => Id, error => #{code => Code, message => Message}}.
