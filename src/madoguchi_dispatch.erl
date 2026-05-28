-module(madoguchi_dispatch).
-moduledoc """
The pure JSON-RPC dispatcher. `handle/2` takes a decoded MCP message and a
server definition and returns `{reply, Response}` or `noreply` (for a
notification). No transport, no sockets - feed it maps and assert the responses.

Implements the `2025-06-18` MCP methods needed for tools: `initialize`, `ping`,
`tools/list`, `tools/call`, and the `notifications/initialized` notification.
""".

-export([handle/2, protocol_version/0]).

-define(PROTOCOL, ~"2025-06-18").

-doc "The MCP protocol revision this server speaks.".
-spec protocol_version() -> binary().
protocol_version() -> ?PROTOCOL.

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
        capabilities => #{tools => #{}},
        serverInfo => #{name => maps:get(name, Server), version => maps:get(version, Server)}
    });
request(~"ping", _Params, Id, _Server) ->
    result(Id, #{});
request(~"tools/list", _Params, Id, Server) ->
    Tools = [madoguchi_tool:to_spec(M) || M <- maps:get(tools, Server, [])],
    result(Id, #{tools => Tools});
request(~"tools/call", Params, Id, Server) ->
    tools_call(Params, Id, Server);
request(_Method, _Params, Id, _Server) ->
    error_response(Id, -32601, ~"Method not found").

tools_call(Params, Id, Server) ->
    Name = maps:get(~"name", Params, undefined),
    Arguments = maps:get(~"arguments", Params, #{}),
    case find_tool(Name, maps:get(tools, Server, [])) of
        {ok, Mod} ->
            case madoguchi_tool:invoke(Mod, Arguments) of
                {ok, Content} ->
                    result(Id, #{content => Content, isError => false});
                {error, Message} ->
                    result(Id, #{content => [madoguchi_tool:text(Message)], isError => true})
            end;
        error ->
            error_response(Id, -32602, iolist_to_binary([~"Unknown tool: ", to_bin(Name)]))
    end.

find_tool(Name, Tools) when is_binary(Name) ->
    case [M || M <- Tools, M:name() =:= Name] of
        [Mod | _] -> {ok, Mod};
        [] -> error
    end;
find_tool(_Name, _Tools) ->
    error.

%% v0.1 supports one revision: echo it when the client requests it, otherwise
%% advertise ours and let the client decide whether to proceed.
negotiate(#{~"protocolVersion" := ?PROTOCOL}) -> ?PROTOCOL;
negotiate(_Params) -> ?PROTOCOL.

result(Id, Result) ->
    #{jsonrpc => ~"2.0", id => Id, result => Result}.

error_response(Id, Code, Message) ->
    #{jsonrpc => ~"2.0", id => Id, error => #{code => Code, message => Message}}.

to_bin(B) when is_binary(B) -> B;
to_bin(undefined) -> ~"(none)";
to_bin(Other) -> iolist_to_binary(io_lib:format("~tp", [Other])).
