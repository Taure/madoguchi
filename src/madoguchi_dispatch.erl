-module(madoguchi_dispatch).
-moduledoc """
The pure JSON-RPC dispatcher. `handle/2` takes a decoded MCP message and a
server definition and returns `{reply, Response}` or `noreply` (for a
notification). No transport, no sockets - feed it maps and assert the responses.

Targets MCP revision `2025-11-25` and negotiates `2025-06-18` for older clients.
Methods: `initialize`, `ping`, `tools/list`, `tools/call`, `resources/list`,
`resources/templates/list`, `resources/read`, `prompts/list`, `prompts/get`, and
the `notifications/initialized` notification.
""".

-include_lib("kernel/include/logger.hrl").

-export([handle/2, protocol_version/0, supported_versions/0]).

-define(PROTOCOL, ~"2025-11-25").
-define(SUPPORTED, [~"2025-11-25", ~"2025-06-18"]).

-doc "The default (latest) MCP protocol revision this server speaks.".
-spec protocol_version() -> binary().
protocol_version() -> ?PROTOCOL.

-doc "All MCP protocol revisions this server can negotiate, newest first.".
-spec supported_versions() -> [binary()].
supported_versions() -> ?SUPPORTED.

-doc "Route one decoded JSON-RPC message against a server definition.".
-spec handle(map(), madoguchi:server()) -> {reply, map()} | noreply.
handle(Msg, Server) ->
    %% No `id` means a notification: never reply, even if it is malformed.
    case maps:is_key(~"id", Msg) of
        false -> noreply;
        true -> {reply, reply_to(Msg, Server)}
    end.

reply_to(#{~"method" := Method} = Msg, Server) ->
    request(Method, maps:get(~"params", Msg, #{}), maps:get(~"id", Msg), Server);
reply_to(#{~"id" := Id}, _Server) ->
    error_response(Id, -32600, ~"Invalid Request").

request(~"initialize", Params, Id, Server) ->
    result(Id, #{
        protocolVersion => negotiate(Params),
        capabilities => capabilities(Server),
        serverInfo => server_info(Server)
    });
request(~"ping", _Params, Id, _Server) ->
    result(Id, #{});
request(~"tools/list", _Params, Id, Server) ->
    Tools = [madoguchi_tool:to_spec(M) || M <- maps:get(tools, Server, [])],
    result(Id, #{tools => Tools});
request(~"tools/call", Params, Id, Server) ->
    tools_call(Params, Id, Server);
request(~"resources/list", _Params, Id, Server) ->
    Resources = madoguchi_resource:list(maps:get(resources, Server, [])),
    result(Id, #{resources => Resources});
request(~"resources/templates/list", _Params, Id, Server) ->
    Templates = madoguchi_resource:templates(maps:get(resources, Server, [])),
    result(Id, #{resourceTemplates => Templates});
request(~"resources/read", Params, Id, Server) ->
    resources_read(Params, Id, Server);
request(~"prompts/list", _Params, Id, Server) ->
    Prompts = [madoguchi_prompt:to_spec(M) || M <- maps:get(prompts, Server, [])],
    result(Id, #{prompts => Prompts});
request(~"prompts/get", Params, Id, Server) ->
    prompts_get(Params, Id, Server);
request(_Method, _Params, Id, _Server) ->
    error_response(Id, -32601, ~"Method not found").

server_info(Server) ->
    Base = #{name => maps:get(name, Server), version => maps:get(version, Server)},
    Optional = maps:with([title, icons], Server),
    maps:merge(Base, Optional).

capabilities(Server) ->
    Base = #{tools => #{}},
    WithResources = maybe_cap(resources, Server, Base),
    maybe_cap(prompts, Server, WithResources).

maybe_cap(Key, Server, Caps) ->
    case maps:get(Key, Server, []) of
        [] -> Caps;
        _ -> Caps#{Key => #{}}
    end.

prompts_get(Params, Id, Server) ->
    case madoguchi_prompt:get(maps:get(prompts, Server, []), Params) of
        {ok, Result} ->
            result(Id, Result);
        not_found ->
            error_response(Id, -32602, ~"Unknown prompt");
        {error, Message} ->
            ?LOG_ERROR(#{event => mcp_prompt_get_failed, reason => Message}),
            error_response(Id, -32603, ~"Prompt rendering failed")
    end.

resources_read(Params, Id, Server) ->
    case maps:get(~"uri", Params, undefined) of
        Uri when is_binary(Uri) ->
            case madoguchi_resource:read(maps:get(resources, Server, []), Uri) of
                {ok, Contents} ->
                    result(Id, #{contents => Contents});
                not_found ->
                    error_response(Id, -32002, ~"Resource not found");
                {error, Message} ->
                    ?LOG_ERROR(#{event => mcp_resource_read_failed, uri => Uri, reason => Message}),
                    error_response(Id, -32603, ~"Resource read failed")
            end;
        _ ->
            error_response(Id, -32602, ~"Invalid params: uri is required")
    end.

tools_call(Params, Id, Server) ->
    Name = maps:get(~"name", Params, undefined),
    Arguments = maps:get(~"arguments", Params, #{}),
    case find_tool(Name, maps:get(tools, Server, [])) of
        {ok, Mod} ->
            case madoguchi_tool:invoke(Mod, Arguments) of
                {ok, Content} ->
                    result(Id, #{content => Content, isError => false});
                {ok, Content, Structured} ->
                    result(Id, #{
                        content => Content, structuredContent => Structured, isError => false
                    });
                {error, Message} ->
                    result(Id, #{content => [madoguchi_tool:text(Message)], isError => true})
            end;
        error ->
            error_response(Id, -32602, ~"Unknown tool")
    end.

find_tool(Name, Tools) when is_binary(Name) ->
    case [M || M <- Tools, M:name() =:= Name] of
        [Mod | _] -> {ok, Mod};
        [] -> error
    end;
find_tool(_Name, _Tools) ->
    error.

%% Echo the client's requested revision when we support it, otherwise advertise
%% our latest and let the client decide whether to proceed.
negotiate(#{~"protocolVersion" := Requested}) when is_binary(Requested) ->
    case lists:member(Requested, ?SUPPORTED) of
        true -> Requested;
        false -> ?PROTOCOL
    end;
negotiate(_Params) ->
    ?PROTOCOL.

result(Id, Result) ->
    #{jsonrpc => ~"2.0", id => Id, result => Result}.

error_response(Id, Code, Message) ->
    #{jsonrpc => ~"2.0", id => Id, error => #{code => Code, message => Message}}.
