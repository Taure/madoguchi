-module(madoguchi_prompt_tests).
-include_lib("eunit/include/eunit.hrl").

server() ->
    #{
        name => ~"prompt-test",
        version => ~"1.0.0",
        tools => [echo_tool],
        prompts => [greeting_prompt]
    }.

bare_server() ->
    #{name => ~"bare", version => ~"1.0.0", tools => [echo_tool]}.

req(Method, Params) ->
    #{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => Method, ~"params" => Params}.

capabilities_advertise_prompts_test() ->
    {reply, #{result := #{capabilities := Caps}}} =
        madoguchi:dispatch(req(~"initialize", #{}), server()),
    ?assertMatch(#{tools := #{}, prompts := #{}}, Caps).

capabilities_omit_prompts_when_none_test() ->
    {reply, #{result := #{capabilities := Caps}}} =
        madoguchi:dispatch(req(~"initialize", #{}), bare_server()),
    ?assertEqual(false, maps:is_key(prompts, Caps)).

prompts_list_test() ->
    {reply, #{result := #{prompts := Prompts}}} =
        madoguchi:dispatch(req(~"prompts/list", #{}), server()),
    ?assertMatch(
        [#{name := ~"greeting", description := _, arguments := [#{name := ~"who"}]}], Prompts
    ).

prompts_list_empty_without_providers_test() ->
    {reply, #{result := #{prompts := Prompts}}} =
        madoguchi:dispatch(req(~"prompts/list", #{}), bare_server()),
    ?assertEqual([], Prompts).

prompts_get_ok_test() ->
    Params = #{~"name" => ~"greeting", ~"arguments" => #{~"who" => ~"Sam"}},
    {reply, #{result := Result}} = madoguchi:dispatch(req(~"prompts/get", Params), server()),
    ?assertMatch(
        #{
            description := ~"A greeting",
            messages := [#{role := user, content := #{type := text, text := ~"Say hi to Sam"}}]
        },
        Result
    ).

prompts_get_unknown_test() ->
    Params = #{~"name" => ~"nope", ~"arguments" => #{}},
    {reply, Resp} = madoguchi:dispatch(req(~"prompts/get", Params), server()),
    ?assertMatch(#{error := #{code := -32602}}, Resp).

prompts_get_render_error_is_generic_test() ->
    Params = #{~"name" => ~"greeting", ~"arguments" => #{}},
    {reply, Resp} = madoguchi:dispatch(req(~"prompts/get", Params), server()),
    ?assertMatch(#{error := #{code := -32603, message := ~"Prompt rendering failed"}}, Resp).

prompts_get_crash_is_generic_test() ->
    Params = #{~"name" => ~"greeting", ~"arguments" => #{~"crash" => true}},
    {reply, Resp} = madoguchi:dispatch(req(~"prompts/get", Params), server()),
    ?assertMatch(#{error := #{code := -32603}}, Resp).
