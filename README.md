```text
  ____    _    ____   ____ _   _ _____   __  __  ____ ____  
 / ___|  / \  |  _ \ / ___| | | |_   _| |  \/  |/ ___|  _ \ 
| |     / _ \ | |_) | |   | | | | | |   | |\/| | |   | |_) |
| |___ / ___ \|  __/| |___| |_| | | |   | |  | | |___|  __/ 
 \____/_/   \_\_|    \____|\___/  |_|   |_|  |_|\____|_|    
```

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) server for CapCut, written in Elixir. Lets Claude read and edit CapCut projects directly -- no CapCut API needed. Works by reading and writing CapCut's local JSON project files.

Built just for fun in a "crazy" language. Elixir/OTP with GenServers, supervision trees, pattern matching and pipes everywhere.

## What it does

Claude gets 15 tools to work with your CapCut projects:

**Read & Inspect**

| Tool | What Claude can do |
|------|--------------------|
| `list_projects` | Show all your CapCut drafts |
| `get_project` | Inspect canvas size, FPS, duration, track count |
| `get_timeline` | See all tracks, clips, and their timecodes |
| `read_draft_json` | Return the full raw project JSON for debugging |

**Create & Add**

| Tool | What Claude can do |
|------|--------------------|
| `create_project` | Create a new empty draft (custom size/FPS) |
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

- Windows (CapCut stores projects in `%LOCALAPPDATA%\CapCut\`)
- [Erlang/OTP 28](https://www.erlang.org/downloads) installed
- Elixir 1.19+ (see [Installation](#installation))
- CapCut desktop app installed

## Installation

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

**3. Clone and build:**
```bash
git clone https://github.com/burnshall-ui/capcut-mcp.git
cd capcut-mcp
mix deps.get
mix compile
```

**4. Smoke test:**
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | mix run --no-halt
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

### Claude Desktop

Claude Desktop ignores the `cwd` config field on Windows, so `mix run` wouldn't find `mix.exs`. The fix is a small wrapper script that changes into the project directory first.

The repo ships a `start-mcp.bat` that does exactly that. Edit it to point at your Elixir installation if it differs from the default:

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

Restart Claude Desktop.

## Configuration

By default the server looks for CapCut projects at:
```text
C:\Users\<you>\AppData\Local\CapCut\User Data\Projects\com.lveditor.draft
```

Override with the `CAPCUT_PATH` environment variable:
```bash
CAPCUT_PATH="D:\CapCut\Projects" mix run --no-halt
```

Blend mode discovery reads CapCut's local app resources from:
```text
C:\Users\<you>\AppData\Local\CapCut\Apps
```

Usually you do not need to configure this manually on Windows because it is derived from `%LOCALAPPDATA%`.
If your CapCut installation lives elsewhere, override it with `CAPCUT_APPS_PATH`:
```bash
CAPCUT_APPS_PATH="D:\PortableApps\CapCut\Apps" mix run --no-halt
```

## Architecture

```text
Claude (stdin/stdout JSON-RPC 2.0)
  └── MCP.Server          GenServer -- stdin loop, dispatches messages
        └── MCP.Dispatcher  Pure -- routes tool calls by name
              └── Tools.*       Pure -- one module per tool (15 tools)
                    ├── TimelineHelper  Shared -- segment lookup, validation, UUID
                    ├── BlendModes      ETS-cached -- discovers CapCut MixMode resources
                    └── ProjectStore    GenServer -- project cache + disk I/O
                          ├── Reader  Pure -- reads JSON files
                          └── Writer  Pure -- writes JSON files (atomic + backup)
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

Every `tools/call` goes through `:telemetry.span/3` in `CapcutMcp.MCP.Dispatcher`, so duration and outcome are exposed as structured events — no custom logging plumbing in individual tools.

Emitted events:

| Event                                              | Measurements                        | Metadata                               |
|----------------------------------------------------|-------------------------------------|----------------------------------------|
| `[:capcut_mcp, :tool, :execute, :start]`           | `:system_time`, `:monotonic_time`   | `:tool`, `:request_id`                 |
| `[:capcut_mcp, :tool, :execute, :stop]`            | `:duration`, `:monotonic_time`      | `:tool`, `:request_id`, `:result`, `:reason?` |
| `[:capcut_mcp, :tool, :execute, :exception]`       | `:duration`, `:monotonic_time`      | `:tool`, `:request_id`, `:kind`, `:reason`, `:stacktrace` |

A default log handler in `CapcutMcp.Telemetry` is attached on boot and prints one line per call, e.g.:

```text
12:34:56.789 [info] tool=add_text request_id=42 result=ok duration=8.24ms
```

`Logger.metadata` is populated early in the pipeline (`mcp_request_id`, `mcp_method`, `tool`, `request_id`), so every log line further down the stack — including inside individual tools — is filterable by request.

To pipe events into Prometheus, OpenTelemetry, Datadog, etc., attach your own handler; the tool code does not need to change.

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
- **ExUnit** -- 82 tests (incl. JSON-RPC integration tests with telemetry assertions)
- **ExCoveralls** -- ~73% line coverage on application code (uncovered paths are mostly stdin-loop I/O and lazy disk helpers)
