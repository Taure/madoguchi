-module(madoguchi_tool_tests).
-include_lib("eunit/include/eunit.hrl").

server() ->
    #{name => ~"tool-test", version => ~"1.0.0", tools => [echo_tool, rich_tool]}.

req(Method, Params) ->
    #{~"jsonrpc" => ~"2.0", ~"id" => 1, ~"method" => Method, ~"params" => Params}.

call(Mode) ->
    Params = #{~"name" => ~"rich", ~"arguments" => #{~"mode" => Mode}},
    {reply, #{result := Result}} = madoguchi:dispatch(req(~"tools/call", Params), server()),
    Result.

%% --- to_spec enrichment ---

spec_includes_annotations_and_schemas_test() ->
    Spec = madoguchi_tool:to_spec(rich_tool),
    ?assertMatch(
        #{
            name := ~"rich",
            title := ~"Rich Tool",
            outputSchema := #{~"type" := ~"object"},
            annotations := #{readOnlyHint := true, idempotentHint := true}
        },
        Spec
    ).

plain_tool_spec_omits_optional_fields_test() ->
    Spec = madoguchi_tool:to_spec(echo_tool),
    ?assertEqual(false, maps:is_key(annotations, Spec)),
    ?assertEqual(false, maps:is_key(outputSchema, Spec)),
    ?assertEqual(false, maps:is_key(icons, Spec)),
    ?assertEqual(false, maps:is_key(title, Spec)).

spec_includes_icons_test() ->
    Spec = madoguchi_tool:to_spec(rich_tool),
    ?assertMatch(#{icons := [#{src := ~"https://example.com/icon.png"}]}, Spec).

%% --- structured output ---

structured_content_in_result_test() ->
    Result = call(~"structured"),
    ?assertMatch(
        #{
            content := [#{type := text, text := ~"scored"}],
            structuredContent := #{~"score" := 42},
            isError := false
        },
        Result
    ).

plain_result_has_no_structured_content_test() ->
    Result = call(~"plain"),
    ?assertEqual(false, maps:is_key(structuredContent, Result)).

%% --- rich content blocks ---

image_content_block_test() ->
    Result = call(~"image"),
    ?assertMatch(
        #{content := [#{type := image, data := ~"AAAA", mimeType := ~"image/png"}]}, Result
    ).

resource_link_content_block_test() ->
    Result = call(~"link"),
    ?assertMatch(#{content := [#{type := resource_link, uri := ~"mem://x"}]}, Result).

%% --- content constructors ---

content_constructors_test() ->
    ?assertEqual(#{type => text, text => ~"a"}, madoguchi_tool:text(~"a")),
    ?assertEqual(
        #{type => audio, data => ~"d", mimeType => ~"audio/wav"},
        madoguchi_tool:audio(~"d", ~"audio/wav")
    ),
    ?assertEqual(
        #{type => resource, resource => #{uri => ~"u"}},
        madoguchi_tool:embedded(#{uri => ~"u"})
    ).
