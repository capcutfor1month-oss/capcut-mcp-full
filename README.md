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

Claude gets 7 tools to work with your CapCut projects:

| Tool | What Claude can do |
|------|--------------------|
| `list_projects` | Show all your CapCut drafts |
| `get_project` | Inspect canvas size, FPS, duration, track count |
| `get_timeline` | See all tracks, clips, and their timecodes |
| `create_project` | Create a new empty draft (custom size/FPS) |
| `add_text` | Add a text overlay at a specific time |
| `add_clip` | Add a video or audio file to the timeline |
| `remove_clip` | Remove a clip by its segment ID |

Example prompts once connected:
- "List my CapCut projects"
- "Add the text 'Intro' to project X at 0ms for 3 seconds"
- "Show me the timeline of my latest project"
- "Create a new 1080x1920 vertical project called 'Reel'"

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
git clone https://github.com/your-username/capcut-mcp.git
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

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

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

## Architecture

```text
Claude (stdin/stdout JSON-RPC 2.0)
  └── MCP.Server          GenServer -- stdin loop, dispatches messages
        └── MCP.Dispatcher  Pure -- routes tool calls by name
              └── Tools.*       Pure -- one module per tool
                    └── ProjectStore  GenServer -- project cache + disk I/O
                          ├── Reader  Pure -- reads JSON files
                          └── Writer  Pure -- writes JSON files (atomic + backup)
```

OTP supervision tree:
```text
CapcutMcp.Application
  ├── CapCut.ProjectStore  (permanent)
  └── MCP.Server           (permanent)
```

If either process crashes, the supervisor restarts it automatically. The `ProjectStore` caches parsed project JSON in memory so tool calls after the first don't re-read the disk.

Every write to `draft_content.json` creates a `.bak` backup and uses an atomic rename (write `.tmp` -> rename) to prevent corruption if the process is killed mid-write.

## Development

```bash
# Run tests
mix test

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
- **ExUnit** -- 44 tests
