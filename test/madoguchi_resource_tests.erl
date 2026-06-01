-module(madoguchi_resource_tests).
-include_lib("eunit/include/eunit.hrl").

server() ->
    #{
        name => ~"res-test",
        version => ~"1.0.0",
        tools => [echo_tool],
        resources => [doc_resources]
    }.

bare_server() ->
    #{name => ~"bare", version => ~"1.0.0", tools => [echo_tool]}.

req(Method, Params) ->
    #{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => Method, ~"params" => Params}.

capabilities_advertise_resources_test() ->
    {reply, #{result := #{capabilities := Caps}}} =
        madoguchi:dispatch(req(~"initialize", #{}), server()),
    ?assertMatch(#{tools := #{}, resources := #{}}, Caps).

capabilities_omit_resources_when_none_test() ->
    {reply, #{result := #{capabilities := Caps}}} =
        madoguchi:dispatch(req(~"initialize", #{}), bare_server()),
    ?assertEqual(false, maps:is_key(resources, Caps)).

resources_list_test() ->
    {reply, #{result := #{resources := Resources}}} =
        madoguchi:dispatch(req(~"resources/list", #{}), server()),
    ?assertMatch([#{uri := ~"mem://greeting", name := ~"greeting"}], Resources).

resources_list_empty_without_providers_test() ->
    {reply, #{result := #{resources := Resources}}} =
        madoguchi:dispatch(req(~"resources/list", #{}), bare_server()),
    ?assertEqual([], Resources).

resources_templates_list_test() ->
    {reply, #{result := #{resourceTemplates := Templates}}} =
        madoguchi:dispatch(req(~"resources/templates/list", #{}), server()),
    ?assertMatch([#{uriTemplate := ~"mem://doc/{id}"}], Templates).

resources_read_ok_test() ->
    {reply, #{result := #{contents := Contents}}} =
        madoguchi:dispatch(req(~"resources/read", #{~"uri" => ~"mem://greeting"}), server()),
    ?assertMatch([#{uri := ~"mem://greeting", text := ~"hello"}], Contents).

resources_read_template_instance_test() ->
    {reply, #{result := #{contents := Contents}}} =
        madoguchi:dispatch(req(~"resources/read", #{~"uri" => ~"mem://doc/1"}), server()),
    ?assertMatch([#{text := ~"doc one"}], Contents).

resources_read_not_found_test() ->
    {reply, Resp} =
        madoguchi:dispatch(req(~"resources/read", #{~"uri" => ~"mem://nope"}), server()),
    ?assertMatch(#{error := #{code := -32002}}, Resp).

resources_read_missing_uri_test() ->
    {reply, Resp} = madoguchi:dispatch(req(~"resources/read", #{}), server()),
    ?assertMatch(#{error := #{code := -32602}}, Resp).

resources_read_crash_is_generic_error_test() ->
    {reply, Resp} =
        madoguchi:dispatch(req(~"resources/read", #{~"uri" => ~"mem://boom"}), server()),
    ?assertMatch(#{error := #{code := -32603, message := ~"Resource read failed"}}, Resp).
