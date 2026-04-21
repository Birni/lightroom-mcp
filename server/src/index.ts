#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import express from "express";
import cors from "cors";
import fs from "fs";
import { extractEmbeddedJpeg, analyzeImage } from "./analyzePhoto.js";

const HTTP_PORT = 8765;

// Request/Response queue management
interface PendingRequest {
  id: string;
  action: string;
  params: any;
  timestamp: number;
}

interface PendingResponse {
  id: string;
  result: any;
  error?: string;
}

const pendingRequests: PendingRequest[] = [];
const pendingResponses: Map<string, PendingResponse> = new Map();
let requestIdCounter = 0;

// Create Express HTTP server for plugin polling
const app = express();
app.use(cors());
app.use(express.json());

// Plugin polls this endpoint for pending requests
app.get("/poll-request", (req, res) => {
  if (pendingRequests.length > 0) {
    const request = pendingRequests.shift()!;
    console.error(`[poll] Delivering request to plugin: ${request.action} (${request.id})`);
    res.json(request);
  } else {
    console.error(`[poll] Plugin polled - no pending requests`);
    res.json({ action: "none" });
  }
});

// Plugin submits responses here
app.post("/submit-response", (req, res) => {
  const { id, result, error } = req.body;

  if (!id) {
    res.status(400).json({ error: "Missing request id" });
    return;
  }

  const resultSummary = result
    ? (result.imageData ? `imageData=${result.imageData.length}chars` : `status=${result.status || "ok"} debug_state=${result.debug_state || "-"} keys=${Object.keys(result).join(",")}`)
    : "no result";
  console.error(`[response] Plugin submitted response for: ${id}${error ? ` (error: ${error})` : ""} | ${resultSummary}`);
  pendingResponses.set(id, { id, result, error });
  res.json({ success: true });
});

// Health check
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    pendingRequests: pendingRequests.length,
    pendingResponses: pendingResponses.size,
  });
});

// Debug endpoint to manually queue a request (for testing)
app.post("/debug/queue-request", (req, res) => {
  const { action, params } = req.body;

  if (!action) {
    res.status(400).json({ error: "Missing action" });
    return;
  }

  const requestId = `req_${Date.now()}_${requestIdCounter++}`;

  const pendingRequest: PendingRequest = {
    id: requestId,
    action,
    params: params || {},
    timestamp: Date.now(),
  };

  pendingRequests.push(pendingRequest);

  res.json({
    success: true,
    requestId,
    message: "Request queued. Plugin will pick it up on next poll."
  });
});

// Debug endpoint to read and drain pending responses (for testing)
app.get("/debug/responses", (req, res) => {
  const all: any[] = [];
  pendingResponses.forEach((v, k) => all.push(v));
  pendingResponses.clear();
  res.json({ count: all.length, responses: all });
});

// Start HTTP server
const httpServer = app.listen(HTTP_PORT, () => {
  console.error(`HTTP server listening on port ${HTTP_PORT}`);
});

httpServer.on("error", (err: NodeJS.ErrnoException) => {
  if (err.code === "EADDRINUSE") {
    console.error(`Port ${HTTP_PORT} already in use. Another instance is running. Exiting.`);
    process.exit(1);
  }
});

// MCP Server setup
const server = new Server(
  {
    name: "lightroom-mcp-server",
    version: "0.1.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "search_photos",
        description: "Search for photos in Lightroom catalog by criteria",
        inputSchema: {
          type: "object",
          properties: {
            filename: {
              type: "string",
              description: "Search by filename (partial match)",
            },
            keywords: {
              type: "array",
              items: { type: "string" },
              description: "Search by keywords",
            },
            rating: {
              type: "number",
              description: "Filter by star rating (0-5)",
              minimum: 0,
              maximum: 5,
            },
            start_date: {
              type: "string",
              description: "Start date (YYYY-MM-DD)",
            },
            end_date: {
              type: "string",
              description: "End date (YYYY-MM-DD)",
            },
          },
        },
      },
      {
        name: "get_photo_metadata",
        description: "Get detailed metadata for a specific photo",
        inputSchema: {
          type: "object",
          properties: {
            photo_id: {
              type: "string",
              description: "Full file path (e.g. E:/pictures/photo.CR3)",
            },
          },
          required: ["photo_id"],
        },
      },
      {
        name: "get_active_photo",
        description: "Get metadata of the currently active/selected photo in Lightroom (the photo open in Develop or selected in Library)",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
      {
        name: "get_photo",
        description: "Get the active photo as a JPEG for quick visual inspection. Returns only the image — no metadata, no analysis. Use analyze_raw_photo or analyze_edit for quantitative data.",
        inputSchema: {
          type: "object",
          properties: {
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
        },
      },
      {
        name: "analyze_raw_photo",
        description: `Pixel-level analysis of the RAW file using its embedded full-res JPEG preview (pre-edit, as shot). Returns quantitative metrics for editing decisions — no image transfer.

Methodology (all luma = BT.709: Y=0.2126R+0.7152G+0.0722B, scaled to 1280px long edge):
- luminance: mean, std, p1/p5/p25/p50/p75/p95/p99, dynamicRangeStops=log2(p99/p1)
- clipping: highlightsClippedPct=luma>250, shadowsClippedPct=luma<5, warnPct thresholds at 245/15
- tonalDistribution (%): blacks<26, shadows<64, darkMids<128, lightMids<192, highlights<230, whites<256
- tonalClusters: dark=luma<p25, mid=p25-p75, bright=luma≥p75 — per cluster: r/g/b/meanLum/bMinusR. tempSpread=bright.bMinusR-dark.bMinusR
- spatial.thirds: [top,mid,bottom] meanLum — geometric thirds, NOT semantic (interpret as sky/mid/ground only for landscape)
- spatial.grid3x3: 3×3 meanLum grid [row][col]
- color.bMinusR: mean(B)-mean(R) — positive=cool, negative=warm
- color.gMinusM: mean(G)-(mean(R)+mean(B))/2 — positive=green cast, negative=magenta
- color.saturation: mean/median/p95 on 0-100 scale. isMonochromatic=median<25
- color.hueDistribution: 8 LR HSL buckets (red=345-15°,orange=15-45°,yellow=45-75°,green=75-165°,aqua=165-195°,blue=195-255°,purple=255-285°,magenta=285-345°), excludes HSV-S<10%. dominant=buckets>5%`,
        inputSchema: {
          type: "object",
          properties: {
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
        },
      },
      {
        name: "analyze_edit",
        description: "Export the active photo with current Lightroom develop settings and run the same pixel analysis as analyze_raw_photo. Returns both the JPEG image (for visual review) and the full analysis JSON. Use after applying edits to verify the result.",
        inputSchema: {
          type: "object",
          properties: {
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
        },
      },
      {
        name: "list_keywords",
        description: "List all keywords in the Lightroom catalog as a tree (name, id, children).",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "list_collections",
        description: "List all collections in Lightroom catalog",
        inputSchema: {
          type: "object",
          properties: {},
        },
      },
      {
        name: "create_collection",
        description: "Create a new collection",
        inputSchema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Collection name",
            },
            parent: {
              type: "string",
              description: "Parent collection set (optional)",
            },
          },
          required: ["name"],
        },
      },
      {
        name: "add_to_collection",
        description: "Add photos to a collection",
        inputSchema: {
          type: "object",
          properties: {
            collection_name: {
              type: "string",
              description: "Collection name",
            },
            photo_ids: {
              type: "array",
              items: { type: "string" },
              description: "Array of full file paths (e.g. E:/pictures/photo.CR3)",
            },
          },
          required: ["collection_name", "photo_ids"],
        },
      },
      {
        name: "set_keywords",
        description: "Add or remove keywords from photos",
        inputSchema: {
          type: "object",
          properties: {
            photo_ids: {
              type: "array",
              items: { type: "string" },
              description: "Array of full file paths (e.g. E:/pictures/photo.CR3)",
            },
            add_keywords: {
              type: "array",
              items: { type: "string" },
              description: "Keywords to add",
            },
            remove_keywords: {
              type: "array",
              items: { type: "string" },
              description: "Keywords to remove",
            },
          },
          required: ["photo_ids"],
        },
      },
      {
        name: "set_rating",
        description: "Set star rating for photos",
        inputSchema: {
          type: "object",
          properties: {
            photo_ids: {
              type: "array",
              items: { type: "string" },
              description: "Array of full file paths (e.g. E:/pictures/photo.CR3)",
            },
            rating: {
              type: "number",
              description: "Star rating (0-5)",
              minimum: 0,
              maximum: 5,
            },
          },
          required: ["photo_ids", "rating"],
        },
      },
      {
        name: "set_develop_settings",
        description: "Apply develop settings to a photo. Only the provided parameters are changed — everything else stays untouched. Set auto_tone or auto_white_balance to true to let Lightroom compute those first, then override with explicit values.\n\nBasic: temperature, tint, exposure, contrast, highlights, shadows, whites, blacks, texture, clarity, dehaze, vibrance, saturation\nTone Curve: tone_darks, tone_lights, tone_shadows, tone_highlights, tone_darks_split, tone_midtone_split, tone_highlights_split\nHSL Hue: hue_red/orange/yellow/green/aqua/blue/purple/magenta\nHSL Saturation: sat_red/orange/yellow/green/aqua/blue/purple/magenta\nHSL Luminance: lum_red/orange/yellow/green/aqua/blue/purple/magenta\nColor Grading: cg_shadow_hue, cg_shadow_sat, cg_shadow_lum, cg_highlight_hue, cg_highlight_sat, cg_highlight_lum, cg_midtone_hue, cg_midtone_sat, cg_midtone_lum, cg_global_hue, cg_global_sat, cg_global_lum, cg_balance, cg_blending\nDetail: sharpness, sharpen_radius, sharpen_detail, sharpen_masking, noise_luminance, noise_color\nEffects: vignette_amount, vignette_midpoint, vignette_feather, vignette_roundness, grain_amount, grain_size, grain_roughness",
        inputSchema: {
          type: "object",
          properties: {
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
            auto_tone: { type: "boolean", description: "Let Lightroom set auto tone before applying other values" },
            auto_white_balance: { type: "boolean", description: "Let Lightroom set auto white balance before applying other values" },
            temperature: { type: "number" }, tint: { type: "number" },
            exposure: { type: "number" }, contrast: { type: "number" },
            highlights: { type: "number" }, shadows: { type: "number" },
            whites: { type: "number" }, blacks: { type: "number" },
            texture: { type: "number" }, clarity: { type: "number" },
            dehaze: { type: "number" }, vibrance: { type: "number" },
            saturation: { type: "number" },
            tone_darks: { type: "number" }, tone_lights: { type: "number" },
            tone_shadows: { type: "number" }, tone_highlights: { type: "number" },
            tone_darks_split: { type: "number" }, tone_midtone_split: { type: "number" },
            tone_highlights_split: { type: "number" },
            hue_red: { type: "number" }, hue_orange: { type: "number" },
            hue_yellow: { type: "number" }, hue_green: { type: "number" },
            hue_aqua: { type: "number" }, hue_blue: { type: "number" },
            hue_purple: { type: "number" }, hue_magenta: { type: "number" },
            sat_red: { type: "number" }, sat_orange: { type: "number" },
            sat_yellow: { type: "number" }, sat_green: { type: "number" },
            sat_aqua: { type: "number" }, sat_blue: { type: "number" },
            sat_purple: { type: "number" }, sat_magenta: { type: "number" },
            lum_red: { type: "number" }, lum_orange: { type: "number" },
            lum_yellow: { type: "number" }, lum_green: { type: "number" },
            lum_aqua: { type: "number" }, lum_blue: { type: "number" },
            lum_purple: { type: "number" }, lum_magenta: { type: "number" },
            cg_shadow_hue: { type: "number" }, cg_shadow_sat: { type: "number" }, cg_shadow_lum: { type: "number" },
            cg_highlight_hue: { type: "number" }, cg_highlight_sat: { type: "number" }, cg_highlight_lum: { type: "number" },
            cg_midtone_hue: { type: "number" }, cg_midtone_sat: { type: "number" }, cg_midtone_lum: { type: "number" },
            cg_global_hue: { type: "number" }, cg_global_sat: { type: "number" }, cg_global_lum: { type: "number" },
            cg_balance: { type: "number" }, cg_blending: { type: "number" },
            sharpness: { type: "number" }, sharpen_radius: { type: "number" },
            sharpen_detail: { type: "number" }, sharpen_masking: { type: "number" },
            noise_luminance: { type: "number" }, noise_color: { type: "number" },
            vignette_amount: { type: "number" }, vignette_midpoint: { type: "number" },
            vignette_feather: { type: "number" }, vignette_roundness: { type: "number" },
            grain_amount: { type: "number" }, grain_size: { type: "number" },
            grain_roughness: { type: "number" },
          },
        },
      },
      {
        name: "reset_develop_settings",
        description: "Reset all develop adjustments to defaults for the active photo in Develop module.",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "create_snapshot",
        description: "Create a develop snapshot to save the current edit state of a photo.",
        inputSchema: {
          type: "object",
          properties: {
            name: { type: "string", description: "Snapshot name" },
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
          required: ["name"],
        },
      },
      {
        name: "list_snapshots",
        description: "List all develop snapshots for a photo.",
        inputSchema: {
          type: "object",
          properties: {
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
        },
      },
      {
        name: "apply_snapshot",
        description: "Restore a saved edit state by applying a develop snapshot.",
        inputSchema: {
          type: "object",
          properties: {
            snapshot_id: { type: "string", description: "Snapshot ID from list_snapshots" },
            photo_id: { type: "string", description: "Full file path (e.g. E:/pictures/photo.CR3). Omit for active photo." },
          },
          required: ["snapshot_id"],
        },
      },
      {
        name: "import_photos",
        description: "Import photos into Lightroom catalog",
        inputSchema: {
          type: "object",
          properties: {
            source_path: {
              type: "string",
              description: "Path to photo or folder to import",
            },
            collection_name: {
              type: "string",
              description: "Collection to add imported photos to (optional)",
            },
            copy_to: {
              type: "string",
              description: "Destination folder for copying files (optional)",
            },
          },
          required: ["source_path"],
        },
      },
      {
        name: "export_photos",
        description: "Export photos from Lightroom",
        inputSchema: {
          type: "object",
          properties: {
            photo_ids: {
              type: "array",
              items: { type: "string" },
              description: "Array of full file paths (e.g. E:/pictures/photo.CR3) to export",
            },
            destination: {
              type: "string",
              description: "Export destination folder",
            },
            format: {
              type: "string",
              description: "Export format (jpeg, png, tiff, original)",
              enum: ["jpeg", "png", "tiff", "original"],
            },
            quality: {
              type: "number",
              description: "JPEG quality (0-100)",
              minimum: 0,
              maximum: 100,
            },
            width: {
              type: "number",
              description: "Max width in pixels (optional)",
            },
            height: {
              type: "number",
              description: "Max height in pixels (optional)",
            },
          },
          required: ["photo_ids", "destination"],
        },
      },
    ],
  };
});

// Handle tool calls - queue request and wait for response
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    // Generate unique request ID
    const requestId = `req_${Date.now()}_${requestIdCounter++}`;

    // Queue the request for plugin to pick up
    const pendingRequest: PendingRequest = {
      id: requestId,
      action: name,
      params: args || {},
      timestamp: Date.now(),
    };

    pendingRequests.push(pendingRequest);

    // Wait for response with timeout (50 seconds — plugin retries internally for up to ~40s)
    const timeoutMs = 50000;
    const startTime = Date.now();

    while (Date.now() - startTime < timeoutMs) {
      if (pendingResponses.has(requestId)) {
        const response = pendingResponses.get(requestId)!;
        pendingResponses.delete(requestId);

        if (response.error) {
          return {
            content: [
              {
                type: "text",
                text: `Error: ${response.error}`,
              },
            ],
            isError: true,
          };
        }

        const res = response.result;

        // Helper: Windows path → WSL path
        const toWslPath = (p: string) =>
          "/mnt/" + p[0].toLowerCase() + p.slice(2).replace(/\\/g, "/");

        // ── get_photo: bare image, no analysis ───────────────────────────
        if (name === "get_photo" && res?.imagePath) {
          const buf = fs.readFileSync(toWslPath(res.imagePath));
          return {
            content: [
              { type: "image", data: buf.toString("base64"), mimeType: "image/jpeg" },
            ],
          };
        }

        // ── analyze_raw_photo: embedded JPEG from RAW → full analysis ────
        if (name === "analyze_raw_photo" && res?.rawPath) {
          const rawWsl = toWslPath(res.rawPath);
          console.error(`[analyze_raw] extracting embedded JPEG from ${rawWsl}`);
          const jpeg = extractEmbeddedJpeg(rawWsl);
          if (!jpeg) {
            return { content: [{ type: "text", text: JSON.stringify({ error: "No embedded JPEG found in RAW file" }) }], isError: true };
          }
          const analysis = await analyzeImage(jpeg, "embedded_jpeg");
          return { content: [{ type: "text", text: JSON.stringify(analysis, null, 2) }] };
        }

        // ── analyze_edit: exported JPEG → image + full analysis ──────────
        if (name === "analyze_edit" && res?.imagePath) {
          const buf = fs.readFileSync(toWslPath(res.imagePath));
          const analysis = await analyzeImage(buf, "exported_jpeg");
          return {
            content: [
              { type: "image", data: buf.toString("base64"), mimeType: "image/jpeg" },
              { type: "text", text: JSON.stringify(analysis, null, 2) },
            ],
          };
        }

        // ── all other tools: return JSON text ────────────────────────────
        return {
          content: [{ type: "text", text: JSON.stringify(res, null, 2) }],
        };
      }

      // Wait 100ms before checking again
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    // Timeout
    return {
      content: [
        {
          type: "text",
          text: `Timeout: Lightroom plugin did not respond within ${timeoutMs / 1000}s. Make sure Lightroom is running with the plugin active.`,
        },
      ],
      isError: true,
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Lightroom MCP server running on stdio");
  console.error(`Plugin should poll: http://localhost:${HTTP_PORT}/poll-request`);

  // Exit when Claude Desktop closes the connection
  process.stdin.on("close", () => {
    console.error("stdin closed, shutting down");
    process.exit(0);
  });
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
