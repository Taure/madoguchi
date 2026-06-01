-module(madoguchi_stdio_tests).
-include_lib("eunit/include/eunit.hrl").

server() ->
    #{name => ~"stdio-test", version => ~"1.0.0", tools => [echo_tool]}.

run(Lines) ->
    Self = self(),
    Reader = make_reader(Lines),
    Writer = fun(Bin) -> Self ! {out, Bin} end,
    ok = madoguchi_stdio:run(server(), #{read => Reader, write => Writer}),
    collect().

make_reader(Lines) ->
    Ref = make_ref(),
    put(Ref, Lines),
    fun() ->
        case get(Ref) of
            [] ->
                eof;
            [H | T] ->
                put(Ref, T),
                H
        end
    end.

collect() ->
    receive
        {out, Bin} -> [json:decode(iolist_to_binary(Bin)) | collect()]
    after 0 -> []
    end.

request_gets_one_response_line_test() ->
    Line = iolist_to_binary(
        json:encode(#{
            ~"jsonrpc" => ~"2.0",
            ~"id" => 1,
            ~"method" => ~"tools/call",
            ~"params" => #{~"name" => ~"echo", ~"arguments" => #{~"message" => ~"hi"}}
        })
    ),
    [Resp] = run([Line]),
    ?assertMatch(#{~"result" := #{~"content" := [#{~"text" := ~"hi"}]}}, Resp).

notification_produces_no_output_test() ->
    Line = iolist_to_binary(
        json:encode(#{~"jsonrpc" => ~"2.0", ~"method" => ~"notifications/initialized"})
    ),
    ?assertEqual([], run([Line])).

blank_line_is_skipped_test() ->
    ?assertEqual([], run([~"", ~"   "])).

multiple_lines_yield_ordered_responses_test() ->
    Ping = iolist_to_binary(
        json:encode(#{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => ~"ping"})
    ),
    Init = iolist_to_binary(
        json:encode(#{~"jsonrpc" => ~"2.0", ~"id" => 2, ~"method" => ~"initialize"})
    ),
    [R1, R2] = run([Ping, Init]),
    ?assertMatch(#{~"id" := 1, ~"result" := #{}}, R1),
    ?assertMatch(#{~"id" := 2, ~"result" := #{~"protocolVersion" := _}}, R2).

parse_error_still_replies_test() ->
    [Resp] = run([~"{ not json"]),
    ?assertMatch(#{~"error" := #{~"code" := -32700}}, Resp).

eof_stops_the_loop_test() ->
    ?assertEqual(
        ok, madoguchi_stdio:run(server(), #{read => fun() -> eof end, write => fun(_) -> ok end})
    ).
