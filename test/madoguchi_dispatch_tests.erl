-module(madoguchi_dispatch_tests).
-include_lib("eunit/include/eunit.hrl").

server() ->
    #{name => ~"test", version => ~"1.0.0", tools => [echo_tool, crash_tool]}.

req(Method, Params) ->
    #{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => Method, ~"params" => Params}.

%% --- initialize ---

initialize_test() ->
    {reply, Resp} = madoguchi:dispatch(req(~"initialize", #{}), server()),
    ?assertMatch(
        #{
            id := 1,
            result := #{
                protocolVersion := ~"2025-06-18",
                capabilities := #{tools := #{}},
                serverInfo := #{name := ~"test", version := ~"1.0.0"}
            }
        },
        Resp
    ).

%% --- ping ---

ping_test() ->
    {reply, Resp} = madoguchi:dispatch(req(~"ping", #{}), server()),
    ?assertMatch(#{id := 1, result := #{}}, Resp).

%% --- tools/list ---

tools_list_test() ->
    {reply, #{result := #{tools := Tools}}} = madoguchi:dispatch(req(~"tools/list", #{}), server()),
    ?assertEqual(2, length(Tools)),
    Names = [maps:get(name, T) || T <- Tools],
    ?assert(lists:member(~"echo", Names)),
    [Echo] = [T || T <- Tools, maps:get(name, T) =:= ~"echo"],
    ?assertMatch(
        #{name := ~"echo", description := _, inputSchema := #{~"type" := ~"object"}}, Echo
    ).

%% --- tools/call ---

tools_call_ok_test() ->
    Params = #{~"name" => ~"echo", ~"arguments" => #{~"message" => ~"hi"}},
    {reply, #{result := Result}} = madoguchi:dispatch(req(~"tools/call", Params), server()),
    ?assertMatch(#{content := [#{type := text, text := ~"hi"}], isError := false}, Result).

tools_call_tool_error_test() ->
    Params = #{~"name" => ~"echo", ~"arguments" => #{}},
    {reply, #{result := Result}} = madoguchi:dispatch(req(~"tools/call", Params), server()),
    ?assertMatch(#{isError := true, content := [#{text := ~"missing message"}]}, Result).

tools_call_crash_is_isolated_test() ->
    Params = #{~"name" => ~"crash", ~"arguments" => #{}},
    {reply, #{result := Result}} = madoguchi:dispatch(req(~"tools/call", Params), server()),
    ?assertMatch(#{isError := true, content := [#{text := <<"tool crashed:", _/binary>>}]}, Result).

tools_call_unknown_tool_test() ->
    Params = #{~"name" => ~"nope", ~"arguments" => #{}},
    {reply, Resp} = madoguchi:dispatch(req(~"tools/call", Params), server()),
    ?assertMatch(#{error := #{code := -32602}}, Resp).

%% --- errors and notifications ---

unknown_method_test() ->
    {reply, Resp} = madoguchi:dispatch(req(~"resources/list", #{}), server()),
    ?assertMatch(#{error := #{code := -32601}}, Resp).

notification_is_noreply_test() ->
    Msg = #{~"jsonrpc" => ~"2.0", ~"method" => ~"notifications/initialized"},
    ?assertEqual(noreply, madoguchi:dispatch(Msg, server())).

malformed_notification_is_noreply_test() ->
    ?assertEqual(noreply, madoguchi:dispatch(#{~"jsonrpc" => ~"2.0"}, server())).

request_without_method_test() ->
    {reply, Resp} = madoguchi:dispatch(#{~"jsonrpc" => ~"2.0", ~"id" => 7}, server()),
    ?assertMatch(#{id := 7, error := #{code := -32600}}, Resp).

parse_error_test() ->
    {reply, Resp} = madoguchi:dispatch(~"{ not json", server()),
    ?assertMatch(#{id := null, error := #{code := -32700}}, Resp).

invalid_request_test() ->
    {reply, Resp} = madoguchi:dispatch(~"[1,2,3]", server()),
    ?assertMatch(#{id := null, error := #{code := -32600}}, Resp).

%% --- raw binary dispatch encodes to valid JSON ---

binary_dispatch_roundtrip_test() ->
    Raw = iolist_to_binary(
        json:encode(
            req(~"tools/call", #{~"name" => ~"echo", ~"arguments" => #{~"message" => ~"yo"}})
        )
    ),
    {reply, Resp} = madoguchi:dispatch(Raw, server()),
    Decoded = json:decode(iolist_to_binary(json:encode(Resp))),
    ?assertMatch(#{~"result" := #{~"isError" := false}}, Decoded).
