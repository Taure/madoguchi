-module(madoguchi_http_tests).
-include_lib("eunit/include/eunit.hrl").

-define(REF, madoguchi_test_http).

server() ->
    #{name => ~"http-test", version => ~"1.0.0", tools => [echo_tool]}.

http_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Port) ->
        [
            ?_test(initialize_over_http(Port)),
            ?_test(tools_call_over_http(Port)),
            ?_test(notification_over_http(Port)),
            ?_test(method_not_allowed_over_http(Port)),
            ?_test(same_host_origin_allowed(Port)),
            ?_test(foreign_origin_rejected(Port)),
            ?_test(bad_accept_rejected(Port)),
            ?_test(json_accept_allowed(Port)),
            ?_test(unsupported_protocol_version_rejected(Port)),
            ?_test(supported_protocol_version_allowed(Port))
        ]
    end}.

setup() ->
    {ok, _} = application:ensure_all_started(cowboy),
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = madoguchi:start_http(server(), #{port => 0, ref => ?REF}),
    ranch:get_port(?REF).

cleanup(_Port) ->
    ok = madoguchi:stop_http(?REF).

post(Port, Map) ->
    post(Port, Map, []).

post(Port, Map, Headers) ->
    Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ "/mcp",
    Body = iolist_to_binary(json:encode(Map)),
    {ok, {{_, Code, _}, _Headers, RespBody}} =
        httpc:request(
            post, {Url, Headers, "application/json", Body}, [], [{body_format, binary}]
        ),
    {Code, RespBody}.

init_req() ->
    #{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => ~"initialize", ~"params" => #{}}.

initialize_over_http(Port) ->
    {Code, Body} = post(Port, #{
        ~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => ~"initialize", ~"params" => #{}
    }),
    ?assertEqual(200, Code),
    ?assertMatch(#{~"result" := #{~"protocolVersion" := ~"2025-11-25"}}, json:decode(Body)).

tools_call_over_http(Port) ->
    {Code, Body} = post(Port, #{
        ~"jsonrpc" => ~"2.0",
        ~"id" => 2,
        ~"method" => ~"tools/call",
        ~"params" => #{~"name" => ~"echo", ~"arguments" => #{~"message" => ~"ping"}}
    }),
    ?assertEqual(200, Code),
    ?assertMatch(
        #{~"result" := #{~"content" := [#{~"text" := ~"ping"}], ~"isError" := false}},
        json:decode(Body)
    ).

notification_over_http(Port) ->
    {Code, _Body} = post(Port, #{~"jsonrpc" => ~"2.0", ~"method" => ~"notifications/initialized"}),
    ?assertEqual(202, Code).

method_not_allowed_over_http(Port) ->
    Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ "/mcp",
    {ok, {{_, Code, _}, _Headers, _Body}} = httpc:request(get, {Url, []}, [], []),
    ?assertEqual(405, Code).

same_host_origin_allowed(Port) ->
    Origin = "http://127.0.0.1:" ++ integer_to_list(Port),
    {Code, _Body} = post(Port, init_req(), [{"origin", Origin}]),
    ?assertEqual(200, Code).

foreign_origin_rejected(Port) ->
    {Code, _Body} = post(Port, init_req(), [{"origin", "http://evil.example.com"}]),
    ?assertEqual(403, Code).

bad_accept_rejected(Port) ->
    {Code, _Body} = post(Port, init_req(), [{"accept", "text/html"}]),
    ?assertEqual(406, Code).

json_accept_allowed(Port) ->
    {Code, _Body} = post(Port, init_req(), [{"accept", "application/json"}]),
    ?assertEqual(200, Code).

unsupported_protocol_version_rejected(Port) ->
    Req = #{~"jsonrpc" => ~"2.0", ~"id" => 9, ~"method" => ~"ping", ~"params" => #{}},
    {Code, _Body} = post(Port, Req, [{"mcp-protocol-version", "1999-01-01"}]),
    ?assertEqual(400, Code).

supported_protocol_version_allowed(Port) ->
    Req = #{~"jsonrpc" => ~"2.0", ~"id" => 9, ~"method" => ~"ping", ~"params" => #{}},
    {Code, _Body} = post(Port, Req, [{"mcp-protocol-version", "2025-06-18"}]),
    ?assertEqual(200, Code).
