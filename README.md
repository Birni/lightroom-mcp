# Lightroom Classic MCP Server

MCP (Model Context Protocol) server for Adobe Lightroom Classic. Interact with your photo catalog using Claude and other AI assistants.

## Features

- **Search Photos**: Find photos by filename, keywords, rating, date range
- **Get Metadata**: Retrieve EXIF data, develop settings, and file information
- **Develop**: Apply develop settings, reset, create and restore snapshots
- **Analyze**: Pixel-level analysis of RAW files and current edits
- **Keywords & Ratings**: Batch add/remove keywords, set star ratings
- **Collections**: List collections and collection sets

## Architecture

HTTP polling architecture — the MCP server runs an HTTP server on port 8765, and the Lightroom plugin polls it every 3 seconds for pending requests.

```
┌─────────────┐    stdio    ┌──────────────────┐    HTTP Poll    ┌──────────────────┐
│   Claude    │ ◄──────────► │   MCP Server     │ ◄──────────────► │ Lightroom Plugin │
│   Desktop   │              │ (HTTP on :8765)  │    (Every 3s)    │  (HTTP Client)   │
└─────────────┘              └──────────────────┘                  └──────────────────┘
```

1. Claude calls an MCP tool via stdio
2. MCP server queues the request with a unique ID
3. Plugin polls `/poll-request` every 3 seconds
4. Plugin executes the Lightroom catalog operation
5. Plugin POSTs response to `/submit-response`
6. MCP server returns result to Claude (50s timeout)

## Prerequisites

- **Lightroom Classic** (tested with v13+)
- **WSL2** (Windows Subsystem for Linux) — the MCP server currently runs in WSL
- **Node.js** 22+ in WSL (managed via mise)
- **mise** — development tool version manager

> **Note:** Native Windows support (running the server directly without WSL) is planned but not yet implemented. Currently, file path conversion from Windows (`E:\photo.CR3`) to WSL (`/mnt/e/photo.CR3`) is hardcoded in the server.

## Installation

### 1. Install Dependencies

```bash
mise trust && mise install
cd server && npm install
```

### 2. Install Lightroom Plugin

1. Copy `plugin/LightroomMCP.lrplugin` to your Lightroom plugins directory:
   - macOS: `~/Library/Application Support/Adobe/Lightroom/Plugins/`
   - Windows: `%APPDATA%\Adobe\Lightroom\Plugins\`
2. Open Lightroom Classic → **File > Plug-in Manager**
3. Click **Add** and select `LightroomMCP.lrplugin`
4. Click **"Start Polling"** in the plugin manager
5. Verify status shows "Polling: true"

### 3. Build MCP Server

```bash
cd server && npm run build
```

### 4. Configure Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json` on Windows. Since the server runs in WSL, use `wsl.exe` as the command:

```json
{
  "mcpServers": {
    "lightroom": {
      "command": "wsl.exe",
      "args": ["node", "/home/YOUR_WSL_USER/lightroom-mcp/server/dist/index.js"]
    }
  }
}
```

### 5. Restart Claude Desktop

## Workflows

The `workflows/` folder contains session choreography guides for working with Claude + Lightroom.

### Using a workflow in Claude Desktop

1. Open the workflow file (e.g. `workflows/LightroomEditWorkflow.md`)
2. Copy the full content
3. In Claude Desktop: open your Project → **Instructions** → paste the content
4. Start a session with: *"Bearbeite das aktive Bild nach Workflow v3.9"*

## Available Tools

| Tool | Description |
|------|-------------|
| `search_photos` | Search by filename, keywords, rating, date |
| `get_photo_metadata` | EXIF data, develop settings, keywords |
| `get_active_photo` | Get the currently active photo in Develop |
| `get_photo` | Export and return photo as image |
| `analyze_raw_photo` | Pixel-level analysis of RAW file |
| `analyze_edit` | Pixel-level analysis of current edit |
| `list_keywords` | List all keywords in the catalog |
| `list_collections` | List all collections and sets |
| `set_keywords` | Add or remove keywords from photos |
| `set_rating` | Set star rating (0–5) |
| `set_develop_settings` | Apply develop adjustments |
| `reset_develop_settings` | Reset all develop adjustments |
| `create_snapshot` | Save current edit state as snapshot |
| `list_snapshots` | List all snapshots for a photo |
| `apply_snapshot` | Restore a saved snapshot |

## Project Structure

```
lightroom-mcp/
├── .mise.toml                    # Tool version management
├── README.md
├── workflows/
│   └── LightroomEditWorkflow.md  # Claude Desktop session guide
├── server/                       # TypeScript MCP server
│   ├── package.json
│   ├── tsconfig.json
│   ├── src/
│   │   ├── index.ts              # MCP server + HTTP endpoints
│   │   └── analyzePhoto.ts       # Pixel analysis
│   └── tests/
│       └── tools.test.ts
└── plugin/
    └── LightroomMCP.lrplugin/
        ├── Info.lua
        ├── PluginInfoProvider.lua  # Polling loop + request routing
        ├── HandlerDevelop.lua
        ├── HandlerMetadata.lua
        ├── HandlerSearch.lua
        ├── HandlerCollections.lua
        ├── HandlerOrganization.lua
        ├── ServerState.lua
        └── JSON.lua
```

## Debugging

### Check Plugin Status

1. Lightroom → **File > Plug-in Manager > Lightroom MCP**
2. Verify "Polling: true" and recent "Last Poll" timestamp
3. Click "Refresh Status" for detailed logs

### Logs

- Plugin: `~/Documents/LrClassicLogs/LightroomMCP.log`
- MCP Server: Claude Desktop logs at `~/Library/Logs/Claude/mcp*.log`

### Common Issues

- **Port already in use**: Kill existing process on port 8765
- **Plugin not polling**: Click "Start Polling" in Plugin Manager
- **Timeout errors**: Ensure Lightroom is open and plugin is active
- **Photos not found**: Use full file paths (e.g. `E:/pictures/photo.CR3`)

## Development

```bash
cd server
npm test       # Run tests
npm run build  # Compile TypeScript
npm run watch  # Watch mode
```

## License

MIT
