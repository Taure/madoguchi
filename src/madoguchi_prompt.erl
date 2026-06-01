-module(madoguchi_prompt).
-moduledoc """
Behaviour for an MCP prompt. A prompt is a named, parameterised message
template a client can list and instantiate.

```erlang
-callback name() -> binary().
-callback description() -> binary().
-callback arguments() -> [argument()].      %% optional
-callback get(Arguments :: map()) ->
    {ok, [message()]} | {ok, binary(), [message()]} | {error, binary()}.
```

`name/0` and `description/0` describe the prompt for `prompts/list`.
`arguments/0` (optional) declares the named arguments a client may supply.
`get/1` receives the decoded `arguments` map and returns the rendered messages,
optionally with a description, or `{error, Message}`.

List prompt modules in the server definition under `prompts`:

```erlang
#{name => ..., version => ..., tools => [...], prompts => [my_prompt]}
```
""".

-export([to_spec/1, get/2, user/1, assistant/1, message/2]).

-export_type([argument/0, message/0, role/0]).

-type role() :: user | assistant.

-type argument() :: #{
    name := binary(),
    description => binary(),
    required => boolean()
}.

-type message() :: #{
    role := role(),
    content := madoguchi_tool:content()
}.

-callback name() -> binary().
-callback description() -> binary().
-callback arguments() -> [argument()].
-callback get(Arguments :: map()) ->
    {ok, [message()]} | {ok, binary(), [message()]} | {error, binary()}.
-callback icons() -> [madoguchi_tool:icon()].

-optional_callbacks([arguments/0, icons/0]).

-doc "Build the `prompts/list` entry for a prompt module.".
-spec to_spec(module()) -> map().
to_spec(Mod) ->
    Base = #{name => Mod:name(), description => Mod:description()},
    WithArgs =
        case prompt_arguments(Mod) of
            [] -> Base;
            Args -> Base#{arguments => Args}
        end,
    maybe_icons(Mod, WithArgs).

prompt_arguments(Mod) ->
    case erlang:function_exported(Mod, arguments, 0) of
        true -> Mod:arguments();
        false -> []
    end.

maybe_icons(Mod, Spec) ->
    case erlang:function_exported(Mod, icons, 0) of
        true -> Spec#{icons => Mod:icons()};
        false -> Spec
    end.

-doc """
Render a prompt by name against a list of prompt modules. Returns the prompt
result, `not_found` if no module matches, or `{error, Message}` on a render
failure. Crashes are caught and reported as a render failure.
""".
-spec get([module()], map()) ->
    {ok, map()} | not_found | {error, binary()}.
get(Prompts, Params) ->
    Name = maps:get(~"name", Params, undefined),
    Arguments = maps:get(~"arguments", Params, #{}),
    case find(Name, Prompts) of
        {ok, Mod} -> render(Mod, Arguments);
        error -> not_found
    end.

find(Name, Prompts) when is_binary(Name) ->
    case [M || M <- Prompts, M:name() =:= Name] of
        [Mod | _] -> {ok, Mod};
        [] -> error
    end;
find(_Name, _Prompts) ->
    error.

render(Mod, Arguments) ->
    try Mod:get(Arguments) of
        {ok, Messages} when is_list(Messages) ->
            {ok, #{messages => Messages}};
        {ok, Description, Messages} when is_binary(Description), is_list(Messages) ->
            {ok, #{description => Description, messages => Messages}};
        {error, Message} when is_binary(Message) ->
            {error, Message};
        Other ->
            {error, iolist_to_binary(io_lib:format("invalid prompt result: ~tp", [Other]))}
    catch
        Class:Reason:_St ->
            {error, iolist_to_binary(io_lib:format("prompt crashed: ~tp:~tp", [Class, Reason]))}
    end.

-doc "Build a user message with a text content block.".
-spec user(binary()) -> message().
user(Text) -> message(user, madoguchi_tool:text(Text)).

-doc "Build an assistant message with a text content block.".
-spec assistant(binary()) -> message().
assistant(Text) -> message(assistant, madoguchi_tool:text(Text)).

-doc "Build a message from a role and a content block.".
-spec message(role(), madoguchi_tool:content()) -> message().
message(Role, Content) -> #{role => Role, content => Content}.
