-module(madoguchi_http_handler).
-moduledoc """
Cowboy request handler for the MCP Streamable HTTP transport. Mount it on a
route with the server definition as the handler state:

```erlang
{"/mcp", madoguchi_http_handler, Server}
```

POST reads the JSON-RPC body, calls `madoguchi:dispatch/2`, and replies
`200 application/json` with the response or `202` for a notification. Other
methods get `405`.

The handler enforces the spec's interop and security MUSTs before dispatching:

- **Origin validation** (DNS-rebinding protection): when an `Origin` header is
  present it must be allowed. By default only same-host origins are accepted;
  configure `allowed_origins` to permit others. A rejected origin gets `403`.
- **`Accept`**: a POST carrying a JSON-RPC request must accept
  `application/json`; otherwise `406`.
- **`MCP-Protocol-Version`**: on any request other than `initialize`, a present
  header must name a version this server speaks; otherwise `400`.

These checks live in the transport, not the pure dispatcher, because they are
HTTP-header concerns.
""".
-behaviour(cowboy_handler).

-include_lib("kernel/include/logger.hrl").

-export([init/2]).

-type state() :: madoguchi:server() | {madoguchi:server(), madoguchi:http_opts()}.

-spec init(cowboy_req:req(), state()) -> {ok, cowboy_req:req(), state()}.
init(Req0, State) ->
    {Server, Opts} = unpack(State),
    Req =
        case cowboy_req:method(Req0) of
            ~"POST" -> guarded_post(Req0, Server, Opts);
            _ -> cowboy_req:reply(405, #{~"allow" => ~"POST"}, ~"", Req0)
        end,
    {ok, Req, State}.

unpack({Server, Opts}) when is_map(Server), is_map(Opts) -> {Server, Opts};
unpack(Server) when is_map(Server) -> {Server, #{}}.

guarded_post(Req0, Server, Opts) ->
    Checks = [fun check_origin/3, fun check_accept/3, fun check_protocol_version/3],
    case run_checks(Checks, Req0, Server, Opts) of
        ok -> handle_post(Req0, Server);
        {error, Code, Message} -> reject(Code, Message, Req0)
    end.

run_checks([], _Req, _Server, _Opts) ->
    ok;
run_checks([Check | Rest], Req, Server, Opts) ->
    case Check(Req, Server, Opts) of
        ok -> run_checks(Rest, Req, Server, Opts);
        {error, _Code, _Message} = Error -> Error
    end.

check_origin(Req, _Server, Opts) ->
    case cowboy_req:header(~"origin", Req) of
        undefined ->
            ok;
        Origin ->
            case origin_allowed(Origin, Req, Opts) of
                true ->
                    ok;
                false ->
                    ?LOG_WARNING(#{event => mcp_origin_rejected, origin => Origin}),
                    {error, 403, ~"Forbidden origin"}
            end
    end.

origin_allowed(Origin, Req, Opts) ->
    case maps:get(allowed_origins, Opts, same_host) of
        any -> true;
        same_host -> same_host_origin(Origin, Req);
        Allowed when is_list(Allowed) -> lists:member(Origin, Allowed)
    end.

same_host_origin(Origin, Req) ->
    OriginHost = origin_host(Origin),
    OriginHost =/= error andalso OriginHost =:= cowboy_req:host(Req).

origin_host(Origin) ->
    case uri_string:parse(Origin) of
        #{host := Host} -> Host;
        _ -> error
    end.

check_accept(Req, _Server, _Opts) ->
    case cowboy_req:header(~"accept", Req) of
        undefined ->
            ok;
        Accept ->
            case accepts_json(Accept) of
                true -> ok;
                false -> {error, 406, ~"Not Acceptable: client must accept application/json"}
            end
    end.

accepts_json(Accept) ->
    Lower = string:lowercase(Accept),
    binary:match(Lower, ~"application/json") =/= nomatch orelse
        binary:match(Lower, ~"*/*") =/= nomatch orelse
        binary:match(Lower, ~"application/*") =/= nomatch.

check_protocol_version(Req, _Server, _Opts) ->
    case cowboy_req:header(~"mcp-protocol-version", Req) of
        undefined ->
            ok;
        Version ->
            case lists:member(Version, madoguchi_dispatch:supported_versions()) of
                true ->
                    ok;
                false ->
                    ?LOG_WARNING(#{event => mcp_unsupported_protocol_version, version => Version}),
                    {error, 400, ~"Unsupported MCP-Protocol-Version"}
            end
    end.

reject(Code, Message, Req) ->
    Body = json:encode(#{
        jsonrpc => ~"2.0",
        id => null,
        error => #{code => -32600, message => Message}
    }),
    cowboy_req:reply(Code, #{~"content-type" => ~"application/json"}, Body, Req).

handle_post(Req0, Server) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case madoguchi:dispatch(Body, Server) of
        {reply, Response} ->
            cowboy_req:reply(
                200, #{~"content-type" => ~"application/json"}, json:encode(Response), Req1
            );
        noreply ->
            cowboy_req:reply(202, #{}, ~"", Req1)
    end.
