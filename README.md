```text
  ____    _    ____   ____ _   _ _____   __  __  ____ ____  
 / ___|  / \  |  _ \ / ___| | | |_   _| |  \/  |/ ___|  _ \ 
| |     / _ \ | |_) | |   | | | | | |   | |\/| | |   | |_) |
| |___ / ___ \|  __/| |___| |_| | | |   | |  | | |___|  __/ 
 \____/_/   \_\_|    \____|\___/  |_|   |_|  |_|\____|_|    
```

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server for CapCut, written in Elixir. Lets Claude read and edit CapCut projects directly -- no CapCut API needed. Works by reading and writing CapCut's local JSON project files.

**"Full" means the write path actually works.** Most CapCut automation tools (this one's own upstream included) can write a schema-correct `draft_info.json` that shows up in CapCut's project list -- and then silently fail to open when you click it, with zero error and zero file access logged. That failure mode has a root cause: `draft_info.json` carries an internal `id` field that has to be the project's *timeline* id, not its project identity -- they're supposed to be two different UUIDs. Every tool we could find (including every earlier version of this one) uses the same UUID for both. This fork fixes that, adds full macOS support (path discovery, `draft_info.json`/`draft_content.json` naming across CapCut versions, the full companion-file scaffold CapCut itself writes for a new project), and verifies live against a real CapCut install that a programmatically-created project actually opens -- not just lists.

Built just for fun in a "crazy" language. Elixir/OTP with GenServers, supervision trees, pattern matching and pipes everywhere.

## What it does

Claude gets 16 tools to work with your CapCut projects:

**Read & Inspect**

| Tool | What Claude can do |
|------|--------------------|
| `list_projects` | Show all your CapCut drafts |
| `get_project` | Inspect canvas size, FPS, duration, track count |
| `get_timeline` | See all tracks, clips, and their timecodes |
| `read_draft_json` | Return the full raw project JSON for debugging |

**Create, Remove & Add**

| Tool | What Claude can do |
|------|--------------------|
| `create_project` | Create a new empty draft (custom size/FPS) -- writes CapCut's full companion-file scaffold and the timeline/project id split so it actually opens, not just lists |
| `remove_project` | Delete a draft (manifest entry + on-disk folder) |
| `add_text` | Add a text overlay at a specific time |
| `add_clip` | Add a video or audio file to the timeline (validates file exists) |

**Modify Clips**

| Tool | What Claude can do |
|------|--------------------|
| `set_clip_transform` | Position, scale, and rotate a clip |
| `set_clip_opacity` | Set clip transparency (0.0 -- 1.0) |
| `set_clip_volume` | Mute, normalize, or boost clip audio |
| `set_clip_loop` | Enable/disable clip looping |
| `set_clip_blend_mode` | Apply blend modes (Screen, Soft Light, Multiply, ...) from your local CapCut install |
| `move_clip` | Reposition a clip on the timeline |
| `trim_clip` | Set source in/out points and timeline duration |
| `remove_clip` | Remove a clip by its segment ID |

Example prompts once connected:
- "List my CapCut projects"
- "Add the text 'Intro' to project X at 0ms for 3 seconds"
- "Show me the timeline of my latest project"
- "Create a new 1080x1920 vertical project called 'Reel'"
- "Set the screen recording clip to Screen blend mode"
- "Move clip X to 5 seconds and set its opacity to 0.8"
- "Mute the video on track 2 and loop the mascot clip"

## Requirements

- **Windows** (CapCut stores projects in `%LOCALAPPDATA%\CapCut\`) or **macOS** (`~/Movies/CapCut/User Data/Projects/com.lveditor.draft`)
- [Erlang/OTP 28](https://www.erlang.org/downloads) installed
- Elixir 1.19+ (see [Installation](#installation))
- CapCut desktop app installed

## Installation

### Windows

**1. Install Erlang OTP** (if not already installed):
```bash
winget install Erlang.ErlangOTP
```

**2. Install Elixir** (no winget package -- download the zip):
```powershell
(New-Object Net.WebClient).DownloadFile(
  'https://github.com/elixir-lang/elixir/releases/download/v1.19.5/elixir-otp-28.zip',
  "$env:USERPROFILE\elixir.zip"
)
Expand-Archive "$env:USERPROFILE\elixir.zip" -DestinationPath "$env:USERPROFILE\elixir"
[Environment]::SetEnvironmentVariable(
  'PATH',
  [Environment]::GetEnvironmentVariable('PATH','User') + ";$env:USERPROFILE\elixir\bin",
  'User'
)
```

### macOS

**1. Install Erlang + Elixir via Homebrew:**
```bash
brew install elixir
```

If `brew link erlang` conflicts with an existing tool of the same name on your `PATH` (this happens if you have an unrelated CLI also named `typer`, `escript`, etc.), don't force-overwrite it -- just scope the PATH for this project instead:
```bash
export PATH="$(brew --prefix erlang)/bin:$PATH"
```

### Both platforms

**3. Clone and build the release:**
```bash
git clone https://github.com/capcutfor1month-oss/capcut-mcp-full.git
cd capcut-mcp-full
mix deps.get
MIX_ENV=prod mix release --overwrite
```

The MCP clients below launch the server via `start-mcp.sh` (macOS/Linux) or
`start-mcp.bat` (Windows), which run the **release** built above — a
self-contained bundle (it even ships its own Erlang runtime) that boots in a
fraction of a second. This matters: the naive `mix run` entrypoint recompiles
and takes the `_build` lock on every launch, which on a cold or external disk
can take several seconds and, when a client spawns more than one instance at
once, makes them block each other — the usual cause of an MCP server that
connects but then times out on the first tool call. Re-run
`MIX_ENV=prod mix release --overwrite` whenever you pull new code.

**4. Smoke test:**
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | ./start-mcp.sh
```

Expected: a JSON response with `"name":"capcut-mcp"`.

## Connecting to Claude

### Claude Code

Create (or edit) `.claude/settings.json` in the project root:

```json
{
  "mcpServers": {
    "capcut": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "C:/Users/<you>/Desktop/kram/capcut-mcp",
      "env": {
        "PATH": "C:\\Program Files\\Erlang OTP\\bin;C:\\Users\\<you>\\elixir\\bin"
      }
    }
  }
}
```

Restart Claude Code -- the `capcut` tools appear automatically.

On macOS, point `command` at the `start-mcp.sh` wrapper (which runs the
self-contained release from step 3 — no `mix`/Elixir needed at runtime):

```json
{
  "mcpServers": {
    "capcut": {
      "command": "/Users/<you>/capcut-mcp-full/start-mcp.sh",
      "env": {
        "PATH": "/usr/bin:/bin"
      }
    }
  }
}
```

### Claude Desktop

Claude Desktop ignores the `cwd` config field, so `mix run` wouldn't find `mix.exs`. The fix is a small wrapper script that changes into the project directory first.

**Windows** -- the repo ships a `start-mcp.bat` that does exactly that. Edit it to point at your Elixir installation if it differs from the default:

```bat
@echo off
cd /d "C:\Users\<you>\Desktop\kram\capcut-mcp"
"C:\Users\<you>\elixir\bin\mix.bat" run --no-halt
```

Then add it to `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "capcut": {
      "command": "C:\\Users\\<you>\\Desktop\\kram\\capcut-mcp\\start-mcp.bat"
    }
  }
}
```

**macOS** -- the repo ships a `start-mcp.sh` (make it executable once with `chmod +x start-mcp.sh`). It launches the self-contained release built in step 3, so it needs no `mix`/Elixir at runtime:

```bash
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/_build/prod/rel/capcut_mcp/bin/capcut_mcp" start
```

Then add it to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "capcut": {
      "command": "/Users/<you>/capcut-mcp-full/start-mcp.sh",
      "env": {
        "PATH": "/usr/bin:/bin"
      }
    }
  }
}
```

Restart Claude Desktop.

## Configuration

`CapcutMcp.CapCut.PathDiscovery` auto-discovers the CapCut projects folder on boot. It checks, in order:

1. The `CAPCUT_PATH` environment variable
2. `%LOCALAPPDATA%\CapCut\User Data\Projects\com.lveditor.draft` — the standard Windows install path
3. `~/Movies/CapCut/User Data/Projects/com.lveditor.draft` — the standard macOS install path

If none resolve to an existing directory, the server still boots. The first tool call that needs disk access returns a descriptive error listing what was tried, so Claude can relay it back to you verbatim.

Override the discovered path (e.g. for a portable install) with `CAPCUT_PATH`:

```bash
# Windows
CAPCUT_PATH="D:\CapCut\Projects\com.lveditor.draft" mix run --no-halt

# macOS
CAPCUT_PATH="/Users/<you>/Movies/CapCut/User Data/Projects/com.lveditor.draft" mix run --no-halt
```

Blend mode discovery reads CapCut's local app resources. On Windows this is derived from `%LOCALAPPDATA%\CapCut\Apps` (one folder per installed CapCut version -- the latest is picked automatically); on macOS it defaults to `/Applications/CapCut.app/Contents/Resources` (a single fixed bundle, verified against a real install -- no per-version folder the way Windows has one). You usually don't need to configure this manually on either platform.

If your CapCut installation lives elsewhere, override it with `CAPCUT_APPS_PATH`:
```bash
# Windows
CAPCUT_APPS_PATH="D:\PortableApps\CapCut\Apps" mix run --no-halt

# macOS
CAPCUT_APPS_PATH="/Users/<you>/Applications/CapCut.app/Contents/Resources" mix run --no-halt
```

`set_clip_blend_mode` is the only tool that needs this; everything else (including `create_project`) works without it.

## Architecture

```text
Claude (stdin/stdout JSON-RPC 2.0)
  └── MCP.Server          GenServer -- stdin loop, dispatches messages
        └── MCP.Dispatcher  Pure -- routes tool calls by name
              └── Tools.*       Pure -- one module per tool (15 tools)
                    ├── TimelineHelper   Shared -- segment lookup, validation, UUID
                    ├── BlendModes       ETS-cached -- discovers CapCut MixMode resources
                    └── ProjectStore     GenServer -- project cache + disk I/O
                          ├── PathDiscovery  Pure -- resolves projects root (env / LOCALAPPDATA)
                          ├── Reader         Pure -- reads JSON files
                          └── Writer         Pure -- writes JSON files (atomic + backup)
```

OTP supervision tree:
```text
CapcutMcp.Application
  ├── CapCut.ProjectStore  (permanent)
  └── MCP.Server           (permanent)
```

If either process crashes, the supervisor restarts it automatically. The `ProjectStore` caches parsed project JSON in memory with read-through loading -- both reads and writes auto-populate the cache on miss, so a GenServer restart is transparent. `BlendModes` caches `MixMode.json` in an ETS table after the first read.

Every write to `draft_content.json` creates a `.bak` backup and uses an atomic rename (write `.tmp` -> rename) to prevent corruption if the process is killed mid-write.

## Observability

Every `tools/call` goes through `:telemetry.span/3` in `CapcutMcp.MCP.Dispatcher`, so duration and outcome are exposed as structured events — no custom logging plumbing in individual tools. The two core subsystems (`ProjectStore` cache and `BlendModes` loader) emit their own events too, and the boundary-hardening pass (Reader path-trust check) emits its own rejection event, so a single telemetry handler can answer "which tool was slow, was it cache-bound or disk-bound, and did any corrupt metadata get filtered on the way in?".

Emitted events:

| Event                                              | Measurements                        | Metadata                               |
|----------------------------------------------------|-------------------------------------|----------------------------------------|
| `[:capcut_mcp, :tool, :execute, :start]`           | `:system_time`, `:monotonic_time`   | `:tool`, `:request_id`                 |
| `[:capcut_mcp, :tool, :execute, :stop]`            | `:duration`, `:monotonic_time`      | `:tool`, `:request_id`, `:result`, `:reason?` |
| `[:capcut_mcp, :tool, :execute, :exception]`       | `:duration`, `:monotonic_time`      | `:tool`, `:request_id`, `:kind`, `:reason`, `:stacktrace` |
| `[:capcut_mcp, :cache, :hit]`                      | `:count` (always `1`)               | `:id`                                  |
| `[:capcut_mcp, :cache, :miss]`                     | `:count` (always `1`)               | `:id`                                  |
| `[:capcut_mcp, :cache, :write]`                    | `:count` (always `1`)               | `:id`, `:reason` (`:load` \| `:update` \| `:create`) |
| `[:capcut_mcp, :blend_modes, :load]`               | `:duration`                         | `:result` (`:ok` \| `:error`), `:count?`, `:path?`, `:reason?` |
| `[:capcut_mcp, :draft, :schema_version]`           | `:count` (always `1`)               | `:version` (`String.t()` \| `nil`), `:supported` (`boolean`) |
| `[:capcut_mcp, :meta, :rejected]`                  | `:count` (always `1`)               | `:reason` (`:path_outside_root`), `:path` (`String.t()`) |

A default log handler in `CapcutMcp.Telemetry` is attached on boot and prints one line per tool call, e.g.:

```text
12:34:56.789 [info] tool=add_text request_id=42 result=ok duration=8.24ms
```

`Logger.metadata` is populated early in the pipeline (`mcp_request_id`, `mcp_method`, `tool`, `request_id`), so every log line further down the stack — including inside individual tools — is filterable by request.

`[:capcut_mcp, :draft, :schema_version]` fires on every successful `read_draft` and additionally triggers a `Logger.warning` when the draft's `new_version` field is missing or not in `CapcutMcp.CapCut.Reader.supported_versions/0` — the server still reads the draft, it just flags that the on-disk schema is untested.

`[:capcut_mcp, :meta, :rejected]` fires when `list_projects` encounters a `root_meta_info.json` entry whose `draft_fold_path` resolves outside the configured `CAPCUT_PATH`. The entry is dropped from the response (so tool callers can't be tricked into reading or writing arbitrary files through a corrupt/malicious meta file), and a `Logger.warning` is emitted alongside the telemetry event.

The cache and blend-modes events are emitted but *not* logged by default (they're chatty on hit paths). Attach your own handler if you want a running hit-rate or a disk-load audit trail:

```elixir
:telemetry.attach_many(
  "my-cache-counter",
  [
    [:capcut_mcp, :cache, :hit],
    [:capcut_mcp, :cache, :miss]
  ],
  fn [_, _, kind], _measurements, _metadata, _cfg ->
    :counters.add(my_counter_ref, kind_to_idx(kind), 1)
  end,
  nil
)
```

To pipe events into Prometheus, OpenTelemetry, Datadog, etc., attach your own handler; the application code does not need to change.

## Development

```bash
# Run tests
mix test

# Code style (strict)
mix credo --strict

# Static analysis (first run builds PLT, ~1-2 min)
mix dialyzer

# Coverage (HTML report at cover/excoveralls.html)
mix coveralls          # console summary
mix coveralls.html     # full HTML report

# Format check
mix format --check-formatted

# Run with a custom CapCut path
CAPCUT_PATH="C:/path/to/projects" mix run --no-halt

# Interactive Elixir shell with the app running
iex -S mix run --no-halt
```

## Known Limitations

- **Export/render** -- not possible via this server (CapCut has no CLI for export; only UI automation could do it)
- **Cloud projects** -- only local drafts are accessible
- **Effects and templates** -- can reference CapCut's built-in effect IDs but can't create new ones; the exact IDs vary by CapCut version
- **CapCut format changes** -- CapCut updates may change the JSON schema; tested against v8.3.0

## Tech Stack

- **Elixir 1.19 / OTP 28** -- because why not
- **Jason** -- JSON encode/decode
- **:telemetry** -- structured events for every tool call
- **Credo** (`--strict`) -- zero issues
- **Dialyzer** (`:underspecs`, `:error_handling`, `:unknown`) -- zero warnings
- **ExUnit** -- 217 tests + 15 `stream_data` property tests + 8 doctests (incl. JSON-RPC integration tests with telemetry assertions on tools + cache + blend-modes + schema-version + meta-rejected events, path-discovery fallbacks for both Windows and macOS, a boundary fuzz test that hammers every registered tool with random `StreamData.term()` arguments, and timeline-mutation invariants like `update_segment` roundtrip, `ensure_timerange` idempotency and `insert_segment` count preservation)
- **StreamData** -- property-based tests for `TimelineHelper` (UUID format, segment roundtrip, track insertion invariants, `validate_timing` domain) and for the `tools/call` request boundary (no random payload may crash the dispatcher)
- **ExCoveralls** -- coverage report on application code (remaining gaps are the stdin-loop I/O layer and a few lazy disk helpers)

## Credits

Started from [burnshall-ui/capcut-mcp](https://github.com/burnshall-ui/capcut-mcp). This fork adds full macOS support (path/blend-mode auto-discovery, the companion-file scaffold CapCut itself writes for a new project) and fixes the write path so a programmatically-created project actually opens in CapCut's editor -- not just lists. See the moduledocs in `lib/capcut_mcp/capcut/draft.ex`, `scaffold.ex`, `project_store.ex`, and `path_discovery.ex` for the full investigation and the confirmed root cause.
