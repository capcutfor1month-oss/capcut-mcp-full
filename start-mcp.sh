#!/bin/sh
# Launch the CapCut MCP server (macOS/Linux) from its self-contained release.
#
# The release under _build/prod/rel/ bundles its own Erlang runtime (erts-*),
# so it needs no system Erlang/Elixir at runtime and boots in a fraction of a
# second with no compile step and no _build lock — unlike `mix run`, which on a
# cold or external disk can take several seconds and, when a client spawns more
# than one at once, serialises them on the build lock (a classic cause of MCP
# "request timed out"). Build/refresh it with:  MIX_ENV=prod mix release --overwrite
DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/_build/prod/rel/capcut_mcp/bin/capcut_mcp"

if [ ! -x "$BIN" ]; then
  echo "capcut-mcp: release not built. Run:  MIX_ENV=prod mix release --overwrite" >&2
  echo "capcut-mcp: (looked for $BIN)" >&2
  exit 1
fi

exec "$BIN" start
