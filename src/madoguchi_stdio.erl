-module(madoguchi_stdio).
-moduledoc """
Newline-delimited JSON-RPC transport over stdin/stdout - the MCP stdio
transport. A line of JSON in on stdin, a line of JSON out on stdout for each
request; notifications produce no output. Every byte of protocol traffic stays
on stdout; logs and diagnostics must go to stderr (the spec forbids anything but
valid MCP messages on stdout).

```erlang
Server = #{name => ~"weather", version => ~"1.0.0", tools => [weather_tool]},
madoguchi_stdio:start(Server).
```

`start/1` runs the read loop in the calling process and returns `ok` at EOF -
use it as the entry point of an escript or a launched node. `start_link/1`
spawns the loop in a linked process and returns its pid for supervision.

The loop is a thin transport: each decoded line goes straight to the pure
`madoguchi_dispatch:handle/2`, so all protocol logic stays testable without a
port. `run/2` exposes that core over explicit `read`/`write` funs for tests and
for embedding over a custom I/O channel.
""".

-include_lib("kernel/include/logger.hrl").

-export([start/1, start_link/1, run/2]).

-type io_funs() :: #{
    read := fun(() -> binary() | eof),
    write := fun((iodata()) -> ok)
}.

-export_type([io_funs/0]).

-doc "Run the stdio read loop in the calling process until EOF on stdin.".
-spec start(madoguchi:server()) -> ok.
start(Server) ->
    run(Server, stdio_funs()).

-doc "Spawn the stdio read loop in a linked process; returns its pid.".
-spec start_link(madoguchi:server()) -> {ok, pid()}.
start_link(Server) ->
    {ok, spawn_link(fun() -> start(Server) end)}.

-doc """
Run the loop over explicit I/O funs. `read` returns one line (a binary, newline
stripped) or `eof`; `write` is given one line to emit (newline appended by the
caller's fun is not required - `run/2` does not add one, the supplied `write`
fun owns framing). Returns `ok` at EOF.
""".
-spec run(madoguchi:server(), io_funs()) -> ok.
run(Server, #{read := Read, write := Write} = Io) ->
    case Read() of
        eof ->
            ok;
        Line ->
            handle_line(Line, Server, Write),
            run(Server, Io)
    end.

handle_line(Line, Server, Write) ->
    case string:trim(Line) of
        ~"" ->
            ok;
        Trimmed ->
            case madoguchi:dispatch(Trimmed, Server) of
                {reply, Response} -> Write(json:encode(Response));
                noreply -> ok
            end
    end.

stdio_funs() ->
    #{
        read => fun read_line/0,
        write => fun write_line/1
    }.

read_line() ->
    case io:get_line(standard_io, ~"") of
        eof ->
            eof;
        {error, Reason} ->
            ?LOG_ERROR(#{event => mcp_stdio_read_error, reason => Reason}),
            eof;
        Data when is_list(Data) -> unicode:characters_to_binary(Data);
        Data when is_binary(Data) -> Data
    end.

write_line(Bin) ->
    io:put_chars(standard_io, [Bin, $\n]).
