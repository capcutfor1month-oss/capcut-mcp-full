# CapCut MCP Server — Design Spec
**Datum:** 2026-04-03  
**Sprache:** Elixir  
**Scope:** Read + Write (Scope B)  
**Ziel:** MCP-Server für CapCut Desktop, kompatibel mit Claude Code und Claude Desktop App

---

## Überblick

Ein MCP-Server in Elixir, der CapCut-Projekte über das lokale Dateisystem liest und schreibt. CapCut speichert alle Projekte als plain JSON (`draft_content.json`), was direkten Zugriff ohne reverse-engineerte APIs ermöglicht. Der Server kommuniziert via stdio (JSON-RPC 2.0) und folgt dem MCP-Protokoll.

---

## Architektur

```
Claude Code / Claude Desktop
        ↓ stdin / stdout (JSON-RPC 2.0)
  ┌─────────────────────┐
  │   MCP.Server        │  ← GenServer: stdio-Loop, Protokoll
  └────────┬────────────┘
           ↓
  ┌─────────────────────┐
  │   MCP.Dispatcher    │  ← Pure Functions: Tool-Calls routen
  └────────┬────────────┘
           ↓
  ┌─────────────────────┐
  │  CapCut.ProjectStore│  ← GenServer: Projekte cachen + State
  └────────┬────────────┘
           ↓
  ┌────────────────────────────┐
  │  CapCut.Reader / .Writer   │  ← Pure Functions: JSON I/O
  └────────────────────────────┘
           ↓
     Filesystem (CapCut User Data)
```

### OTP Supervision Tree

```
CapcutMcp.Application
  ├── CapCut.ProjectStore   (GenServer, :permanent)
  └── MCP.Server            (GenServer, :permanent)
```

`ProjectStore` startet zuerst. Crasht ein Prozess, wird er vom Supervisor neu gestartet ohne den anderen zu beeinflussen.

---

## Verzeichnisstruktur

```
capcut-mcp/
├── mix.exs
├── config/
│   └── config.exs
├── lib/
│   └── capcut_mcp/
│       ├── application.ex          # OTP Application + Supervision Tree
│       ├── mcp/
│       │   ├── server.ex           # GenServer: stdin-Loop + JSON-RPC
│       │   ├── dispatcher.ex       # Pure: Tool-Name → Handler routen
│       │   └── protocol.ex         # Pure: JSON-RPC encode/decode
│       ├── capcut/
│       │   ├── project_store.ex    # GenServer: Cache + Disk-Writes
│       │   ├── reader.ex           # Pure: draft_content.json parsen
│       │   ├── writer.ex           # Pure: JSON bauen + schreiben
│       │   └── types.ex            # Structs: Project, Track, Clip
│       └── tools/
│           ├── list_projects.ex    # Tool: alle Drafts auflisten
│           ├── get_project.ex      # Tool: Projekt-Info lesen
│           ├── get_timeline.ex     # Tool: Tracks + Clips lesen
│           ├── create_project.ex   # Tool: neues Draft anlegen
│           ├── add_clip.ex         # Tool: Video/Audio-Clip einfügen
│           ├── add_text.ex         # Tool: Text-Element einfügen
│           └── remove_clip.ex      # Tool: Clip per ID entfernen
└── test/
    └── capcut_mcp/
        ├── reader_test.exs
        ├── writer_test.exs
        └── tools/
```

---

## MCP Tools

### Read-Tools

| Tool | Parameter | Rückgabe |
|------|-----------|----------|
| `list_projects` | — | Array: `{id, name, duration_ms, modified_at}` |
| `get_project` | `project_id` | Canvas-Config, FPS, Version, Plattform-Info |
| `get_timeline` | `project_id` | Alle Tracks mit Clips, Texten, Materialien |

### Write-Tools

| Tool | Parameter | Aktion |
|------|-----------|--------|
| `create_project` | `name`, `width?`, `height?`, `fps?` | Neues Draft-JSON anlegen (Default: 1920×1080, 30fps) |
| `add_clip` | `project_id`, `file_path`, `track_index?`, `start_ms?`, `duration_ms?` | Video/Audio-Material zu Track hinzufügen |
| `add_text` | `project_id`, `content`, `start_ms`, `duration_ms`, `track_index?` | Text-Element einfügen |
| `remove_clip` | `project_id`, `clip_id` | Clip per ID aus Timeline entfernen |

---

## Datenfluss: Write-Operation (Beispiel `add_text`)

1. Claude ruft `add_text` auf (project_id, content, start_ms, duration_ms)
2. `MCP.Server` empfängt JSON-RPC Request von stdin
3. `MCP.Dispatcher` routet zu `Tools.AddText`
4. `Tools.AddText` ruft `CapCut.ProjectStore.get_project(id)` auf
5. `ProjectStore` gibt gecachtes Draft zurück (oder liest von Disk wenn nicht gecacht)
6. `Tools.AddText` baut Text-Material + Track-Segment JSON (UUIDs via `:crypto`)
7. `Tools.AddText` ruft `CapCut.ProjectStore.update_project(id, updated_draft)` auf
8. `ProjectStore` schreibt `.json` + `.json.bak` auf Disk, aktualisiert Cache
9. `MCP.Server` sendet Success-Response an stdout

---

## Konfiguration

**`config/config.exs`:**
```elixir
config :capcut_mcp,
  capcut_path: System.get_env("CAPCUT_PATH",
    "C:/Users/tspor/AppData/Local/CapCut/User Data/Projects/com.lveditor.draft")
```

---

## Integration

### Claude Desktop

Datei: `%APPDATA%\Claude\claude_desktop_config.json`
```json
{
  "mcpServers": {
    "capcut": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "C:/Users/tspor/Desktop/kram/capcut-mcp"
    }
  }
}
```

### Claude Code

Datei: `.claude/settings.json` (im capcut-mcp Repo)
```json
{
  "mcpServers": {
    "capcut": {
      "command": "mix",
      "args": ["run", "--no-halt"],
      "cwd": "C:/Users/tspor/Desktop/kram/capcut-mcp"
    }
  }
}
```

### Voraussetzung

```
winget install Elixir
```

---

## Fehlerbehandlung

- Projekt nicht gefunden → MCP-Fehler mit `code: -32602` (Invalid params)
- JSON-Parse-Fehler → Fehler loggen, leeres Projekt zurückgeben
- Disk-Schreibfehler → Fehler zurückgeben, Cache nicht aktualisieren (Atomarität)
- Backup (`.json.bak`) vor jedem Write anlegen

---

## Offene Punkte (beim Testen klären)

- Genaues Format für `add_clip` (CapCut erwartet spezifische Material-IDs)
- Welche Felder in `draft_content.json` sind zwingend vs. optional beim Erstellen
- Export/Render: nur via UI-Automation möglich (Playwright), vorerst nicht im Scope
