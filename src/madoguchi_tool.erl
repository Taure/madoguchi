-module(madoguchi_tool).
-moduledoc """
Behaviour for MCP tools. A tool is a module: it names itself, describes itself,
declares a JSON Schema for its arguments, and runs.

`call/1` receives the decoded `arguments` map from a `tools/call` request and
returns `{ok, binary()}` (wrapped as a single text block), `{ok, [content()]}`,
or `{error, binary()}`. An `{error, _}` or a crash is reported to the client as
an MCP tool error (`isError => true`) for that call, never a server failure.
""".

-export([to_spec/1, invoke/2, text/1]).

-export_type([content/0]).

-type content() :: #{type => text, text => binary()}.

-callback name() -> binary().
-callback description() -> binary().
-callback input_schema() -> map().
-callback call(Arguments :: map()) -> {ok, binary()} | {ok, [content()]} | {error, binary()}.

-doc "Build the `tools/list` entry for a tool module.".
-spec to_spec(module()) -> map().
to_spec(Mod) ->
    #{
        name => Mod:name(),
        description => Mod:description(),
        inputSchema => Mod:input_schema()
    }.

-doc "Run a tool, normalising its result to content blocks. Crashes are caught.".
-spec invoke(module(), map()) -> {ok, [content()]} | {error, binary()}.
invoke(Mod, Arguments) ->
    try Mod:call(Arguments) of
        {ok, Bin} when is_binary(Bin) -> {ok, [text(Bin)]};
        {ok, Content} when is_list(Content) -> {ok, Content};
        {error, Message} when is_binary(Message) -> {error, Message};
        Other -> {error, iolist_to_binary(io_lib:format("invalid tool result: ~tp", [Other]))}
    catch
        Class:Reason:_St ->
            {error, iolist_to_binary(io_lib:format("tool crashed: ~tp:~tp", [Class, Reason]))}
    end.

-doc "Build a text content block.".
-spec text(binary()) -> content().
text(Bin) -> #{type => text, text => Bin}.
