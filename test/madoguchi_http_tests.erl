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
            ?_test(method_not_allowed_over_http(Port))
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
    Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ "/mcp",
    Body = iolist_to_binary(json:encode(Map)),
    {ok, {{_, Code, _}, _Headers, RespBody}} =
        httpc:request(post, {Url, [], "application/json", Body}, [], [{body_format, binary}]),
    {Code, RespBody}.

initialize_over_http(Port) ->
    {Code, Body} = post(Port, #{
        ~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => ~"initialize", ~"params" => #{}
    }),
    ?assertEqual(200, Code),
    ?assertMatch(#{~"result" := #{~"protocolVersion" := ~"2025-06-18"}}, json:decode(Body)).

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
