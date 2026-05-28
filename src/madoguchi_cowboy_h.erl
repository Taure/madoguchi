-module(madoguchi_cowboy_h).
-moduledoc """
Cowboy handler for the MCP Streamable HTTP transport. Mount it on a route with
the server definition as the handler state:

```erlang
{"/mcp", madoguchi_cowboy_h, Server}
```

POST reads the JSON-RPC body, calls `madoguchi:dispatch/2`, and replies
`200 application/json` with the response or `202` for a notification. Other
methods get `405`.
""".
-behaviour(cowboy_handler).

-export([init/2]).

-spec init(cowboy_req:req(), madoguchi:server()) -> {ok, cowboy_req:req(), madoguchi:server()}.
init(Req0, Server) ->
    Req =
        case cowboy_req:method(Req0) of
            ~"POST" -> handle_post(Req0, Server);
            _ -> cowboy_req:reply(405, #{~"allow" => ~"POST"}, <<>>, Req0)
        end,
    {ok, Req, Server}.

handle_post(Req0, Server) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case madoguchi:dispatch(Body, Server) of
        {reply, Response} ->
            cowboy_req:reply(
                200, #{~"content-type" => ~"application/json"}, json:encode(Response), Req1
            );
        noreply ->
            cowboy_req:reply(202, #{}, <<>>, Req1)
    end.
