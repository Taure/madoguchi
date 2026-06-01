-module(madoguchi_resource).
-moduledoc """
Behaviour for an MCP resource provider. A provider module advertises a set of
resources (and optional URI templates) and reads them by URI.

```erlang
-callback list() -> [resource()].
-callback templates() -> [template()].   %% optional
-callback read(Uri :: binary()) ->
    {ok, [contents()]} | {error, not_found} | {error, binary()}.
```

`list/0` returns the static resource descriptors a client sees in
`resources/list`. `templates/0` (optional) returns URI-template descriptors for
`resources/templates/list`; a provider that has none can omit it. `read/1`
receives a requested URI and returns its contents, `{error, not_found}` for an
unknown URI (mapped to a JSON-RPC error), or `{error, Message}` for a read
failure.

List providers in the server definition under `resources`:

```erlang
#{name => ..., version => ..., tools => [...], resources => [my_resources]}
```
""".

-export([list/1, templates/1, read/2, text/2, blob/3]).

-export_type([resource/0, template/0, contents/0]).

-type resource() :: #{
    uri := binary(),
    name := binary(),
    description => binary(),
    mimeType => binary(),
    title => binary()
}.

-type template() :: #{
    uriTemplate := binary(),
    name := binary(),
    description => binary(),
    mimeType => binary(),
    title => binary()
}.

-type contents() :: #{
    uri := binary(),
    mimeType => binary(),
    text => binary(),
    blob => binary()
}.

-callback list() -> [resource()].
-callback templates() -> [template()].
-callback read(Uri :: binary()) -> {ok, [contents()]} | {error, not_found} | {error, binary()}.

-optional_callbacks([templates/0]).

-doc "Collect the resource descriptors from a list of provider modules.".
-spec list([module()]) -> [resource()].
list(Providers) ->
    [R || Mod <- Providers, R <- Mod:list()].

-doc "Collect the URI-template descriptors from a list of provider modules.".
-spec templates([module()]) -> [template()].
templates(Providers) ->
    [T || Mod <- Providers, T <- provider_templates(Mod)].

provider_templates(Mod) ->
    case erlang:function_exported(Mod, templates, 0) of
        true -> Mod:templates();
        false -> []
    end.

-doc """
Read a URI against a list of providers. Returns the first provider's contents,
`not_found` if no provider serves the URI, or `{error, Message}` on a read
failure. Crashes are caught and reported as a read failure.
""".
-spec read([module()], binary()) -> {ok, [contents()]} | not_found | {error, binary()}.
read([], _Uri) ->
    not_found;
read([Mod | Rest], Uri) ->
    try Mod:read(Uri) of
        {ok, Contents} when is_list(Contents) -> {ok, Contents};
        {error, not_found} -> read(Rest, Uri);
        {error, Message} when is_binary(Message) -> {error, Message};
        Other -> {error, iolist_to_binary(io_lib:format("invalid resource result: ~tp", [Other]))}
    catch
        Class:Reason:_St ->
            {error,
                iolist_to_binary(io_lib:format("resource read crashed: ~tp:~tp", [Class, Reason]))}
    end.

-doc "Build a text resource-contents block.".
-spec text(binary(), binary()) -> contents().
text(Uri, Text) ->
    #{uri => Uri, mimeType => ~"text/plain", text => Text}.

-doc "Build a binary (base64) resource-contents block.".
-spec blob(binary(), binary(), binary()) -> contents().
blob(Uri, MimeType, Blob) ->
    #{uri => Uri, mimeType => MimeType, blob => Blob}.
