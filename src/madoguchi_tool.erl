-module(madoguchi_tool).
-moduledoc """
Behaviour for MCP tools. A tool is a module: it names itself, describes itself,
declares a JSON Schema for its arguments, and runs.

`call/1` receives the decoded `arguments` map from a `tools/call` request and
returns `{ok, binary()}` (wrapped as a single text block), `{ok, [content()]}`,
`{ok, [content()], StructuredContent :: map()}` (when the tool declares an
`output_schema/0`), or `{error, binary()}`. An `{error, _}` or a crash is
reported to the client as an MCP tool error (`isError => true`) for that call,
never a server failure.

Optional callbacks enrich the `tools/list` entry:

- `title/0` - a human display name distinct from the protocol `name/0`.
- `annotations/0` - behavioural hints (`read_only`, `destructive`, `idempotent`,
  `open_world`, plus a `title`) a client uses to decide how to present or gate
  the tool. Hints, not guarantees.
- `output_schema/0` - a JSON Schema for structured results; when present, a tool
  may return `structuredContent` alongside its content blocks.

Content is not limited to text: build blocks with `text/1`, `image/2`,
`audio/2`, `resource_link/2`, and `embedded/1`.
""".

-export([
    to_spec/1,
    invoke/2,
    text/1,
    image/2,
    audio/2,
    resource_link/2,
    embedded/1
]).

-export_type([content/0, annotations/0]).

-type content() ::
    #{type := text, text := binary()}
    | #{type := image, data := binary(), mimeType := binary()}
    | #{type := audio, data := binary(), mimeType := binary()}
    | #{type := resource_link, uri := binary(), name := binary()}
    | #{type := resource, resource := map()}.

-type annotations() :: #{
    title => binary(),
    readOnlyHint => boolean(),
    destructiveHint => boolean(),
    idempotentHint => boolean(),
    openWorldHint => boolean()
}.

-callback name() -> binary().
-callback description() -> binary().
-callback input_schema() -> map().
-callback call(Arguments :: map()) ->
    {ok, binary()}
    | {ok, [content()]}
    | {ok, [content()], map()}
    | {error, binary()}.
-callback title() -> binary().
-callback annotations() -> annotations().
-callback output_schema() -> map().
-callback icons() -> [icon()].

-optional_callbacks([title/0, annotations/0, output_schema/0, icons/0]).

-type icon() :: #{src := binary(), mimeType => binary(), sizes => binary()}.

-export_type([icon/0]).

-doc "Build the `tools/list` entry for a tool module, including any optional enrichments.".
-spec to_spec(module()) -> map().
to_spec(Mod) ->
    Base = #{
        name => Mod:name(),
        description => Mod:description(),
        inputSchema => Mod:input_schema()
    },
    enrich(Mod, Base).

enrich(Mod, Spec0) ->
    Spec1 = maybe_put(title, Mod, title, Spec0),
    Spec2 = maybe_put(annotations, Mod, annotations, Spec1),
    Spec3 = maybe_put(outputSchema, Mod, output_schema, Spec2),
    maybe_put(icons, Mod, icons, Spec3).

maybe_put(SpecKey, Mod, Fun, Spec) ->
    case erlang:function_exported(Mod, Fun, 0) of
        true -> Spec#{SpecKey => Mod:Fun()};
        false -> Spec
    end.

-doc "Run a tool, normalising its result to content blocks. Crashes are caught.".
-spec invoke(module(), map()) ->
    {ok, [content()]} | {ok, [content()], map()} | {error, binary()}.
invoke(Mod, Arguments) ->
    try Mod:call(Arguments) of
        {ok, Bin} when is_binary(Bin) ->
            {ok, [text(Bin)]};
        {ok, Content} when is_list(Content) ->
            {ok, Content};
        {ok, Content, Structured} when is_list(Content), is_map(Structured) ->
            {ok, Content, Structured};
        {error, Message} when is_binary(Message) ->
            {error, Message};
        Other ->
            {error, iolist_to_binary(io_lib:format("invalid tool result: ~tp", [Other]))}
    catch
        Class:Reason:_St ->
            {error, iolist_to_binary(io_lib:format("tool crashed: ~tp:~tp", [Class, Reason]))}
    end.

-doc "Build a text content block.".
-spec text(binary()) -> content().
text(Bin) -> #{type => text, text => Bin}.

-doc "Build an image content block from base64 data and a MIME type.".
-spec image(binary(), binary()) -> content().
image(Data, MimeType) -> #{type => image, data => Data, mimeType => MimeType}.

-doc "Build an audio content block from base64 data and a MIME type.".
-spec audio(binary(), binary()) -> content().
audio(Data, MimeType) -> #{type => audio, data => Data, mimeType => MimeType}.

-doc "Build a resource-link content block pointing at a resource URI.".
-spec resource_link(binary(), binary()) -> content().
resource_link(Uri, Name) -> #{type => resource_link, uri => Uri, name => Name}.

-doc """
Build an embedded-resource content block. `Resource` is a resource-contents map,
for example one built with `madoguchi_resource:text/2` or `blob/3`.
""".
-spec embedded(map()) -> content().
embedded(Resource) -> #{type => resource, resource => Resource}.
