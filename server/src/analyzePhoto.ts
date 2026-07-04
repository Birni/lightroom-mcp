import sharp from "sharp";
import fs from "fs";

// ── Embedded JPEG extraction ──────────────────────────────────────────────────

/**
 * Scan a RAW file (CR3, CR2, NEF, ARW, DNG …) for JPEG SOI/EOI markers and
 * return the largest embedded JPEG (= full-size preview, ~6 MP on Canon R6).
 */
export function extractEmbeddedJpeg(filePath: string): Buffer | null {
  const data = fs.readFileSync(filePath);
  const SOI = Buffer.from([0xff, 0xd8, 0xff]);
  const EOI = Buffer.from([0xff, 0xd9]);

  let best: { start: number; end: number; size: number } | null = null;
  let idx = 0;
  while (idx < data.length - 2) {
    const start = data.indexOf(SOI, idx);
    if (start === -1) break;
    const end = data.indexOf(EOI, start + 2);
    if (end === -1) { idx = start + 1; continue; }
    const size = end + 2 - start;
    if (!best || size > best.size) best = { start, end: end + 2, size };
    idx = start + 1;
  }
  return best ? data.slice(best.start, best.end) : null;
}

// ── MCP image fitting ─────────────────────────────────────────────────────────

/**
 * Shrink a JPEG (in-memory, via sharp) until it fits under `maxBytes`, so it can
 * be base64-embedded in an MCP response (~1 MB message limit).
 *
 * This replaces the plugin's old multi-step re-export cascade: the plugin now
 * renders the photo ONCE (one mask render) and hands us the result; any size
 * fitting happens here as fast in-memory recompression — not repeated Lightroom
 * renders that took >50s on heavily-masked/textured edits.
 */
export async function fitJpegUnderBytes(buf: Buffer, maxBytes: number): Promise<Buffer> {
  if (buf.length <= maxBytes) return buf;

  const meta = await sharp(buf).metadata();
  const origW = meta.width ?? 1600;

  // Progressively smaller long-edge widths, then lower quality, until it fits.
  for (const targetW of [1400, 1200, 1000, 800, 640]) {
    if (targetW >= origW) continue;
    for (const quality of [72, 60, 50]) {
      const out = await sharp(buf).resize({ width: targetW }).jpeg({ quality }).toBuffer();
      if (out.length <= maxBytes) return out;
    }
  }

  // Last resort — smallest/lowest we allow.
  return await sharp(buf).resize({ width: 640 }).jpeg({ quality: 45 }).toBuffer();
}

// ── Types ─────────────────────────────────────────────────────────────────────

export interface TonalCluster {
  pctOfPixels: number;
  r: number; g: number; b: number;
  meanLum: number;
  bMinusR: number;
}

export interface HueDist {
  red: number; orange: number; yellow: number; green: number;
  aqua: number; blue: number; purple: number; magenta: number;
  unsaturatedPct: number;
  dominant: string[];
}

export interface AnalysisResult {
  source: "embedded_jpeg" | "exported_jpeg";
  dimensions: { width: number; height: number };
  luminance: {
    mean: number; std: number;
    p1: number; p5: number; p25: number; p50: number;
    p75: number; p95: number; p99: number;
    dynamicRangeStops: number;
  };
  clipping: {
    highlightsClippedPct: number;
    shadowsClippedPct: number;
    highlightsWarnPct: number;
    shadowsWarnPct: number;
  };
  tonalDistribution: {
    blacks: number; shadows: number; darkMids: number;
    lightMids: number; highlights: number; whites: number;
  };
  tonalClusters: {
    dark: TonalCluster; mid: TonalCluster; bright: TonalCluster;
    tempSpread: number;
  };
  spatial: {
    thirds: number[];    // [top, mid, bottom] meanLum — geometric thirds
    grid3x3: number[][]; // [row][col] meanLum
  };
  color: {
    means:   { r: number; g: number; b: number };
    medians: { r: number; g: number; b: number };
    bMinusR: number;
    gMinusM: number;
    saturation: { mean: number; median: number; p95: number; isMonochromatic: boolean };
    hueDistribution: HueDist;
  };
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function histPct(hist: Int32Array, total: number, pct: number): number {
  const target = total * pct / 100;
  let cumul = 0;
  for (let i = 0; i < hist.length; i++) {
    cumul += hist[i];
    if (cumul >= target) return i;
  }
  return hist.length - 1;
}

// ── Main analysis ─────────────────────────────────────────────────────────────

export async function analyzeImage(
  imageBuffer: Buffer,
  source: "embedded_jpeg" | "exported_jpeg"
): Promise<AnalysisResult> {

  // Scale to max 1280px long edge — statistics stable, ~50 ms processing
  const origMeta = await sharp(imageBuffer).metadata();
  const origW = origMeta.width  ?? 1280;
  const origH = origMeta.height ?? 720;
  const scale = Math.min(1, 1280 / Math.max(origW, origH));
  const w = Math.round(origW * scale);
  const h = Math.round(origH * scale);

  const { data: px, info } = await sharp(imageBuffer)
    .resize(w, h)
    .rotate()       // apply EXIF orientation tag 0x0112
    .raw()
    .toBuffer({ resolveWithObject: true });

  const ch    = info.channels;  // 3 for JPEG
  const total = w * h;

  // ── histograms & per-pixel accumulators ─────────────────────────────────
  const lumHist = new Int32Array(256);
  const rHist   = new Int32Array(256);
  const gHist   = new Int32Array(256);
  const bHist   = new Int32Array(256);
  const satHist = new Int32Array(101); // 0–100 %
  const hueHist = new Int32Array(360);
  const zoneCnt = new Int32Array(6);
  const ZONE_HI = [26, 64, 128, 192, 230, 256];

  const gridLum = new Float64Array(9);
  const gridN   = new Int32Array(9);
  const cellW   = w / 3;
  const cellH   = h / 3;

  let rSum = 0, gSum = 0, bSum = 0;
  let hlClip = 0, shClip = 0, hlWarn = 0, shWarn = 0;
  let unsaturated = 0;

  // ── single pass ──────────────────────────────────────────────────────────
  for (let i = 0; i < total; i++) {
    const r = px[i * ch], g = px[i * ch + 1], b = px[i * ch + 2];

    // BT.709 luma
    const lum = Math.min(255, Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b));
    lumHist[lum]++;
    rHist[r]++; gHist[g]++; bHist[b]++;
    rSum += r; gSum += g; bSum += b;

    // Clipping
    if (lum > 250) hlClip++;
    if (lum <   5) shClip++;
    if (lum > 245) hlWarn++;
    if (lum <  15) shWarn++;

    // Tonal zones
    for (let z = 0; z < 6; z++) { if (lum < ZONE_HI[z]) { zoneCnt[z]++; break; } }

    // 3×3 spatial grid
    const row = Math.min(2, Math.floor((i / w) / cellH));
    const col = Math.min(2, Math.floor((i % w) / cellW));
    gridLum[row * 3 + col] += lum;
    gridN  [row * 3 + col]++;

    // HSV saturation + hue
    const rn = r / 255, gn = g / 255, bn = b / 255;
    const mx = Math.max(rn, gn, bn), mn = Math.min(rn, gn, bn);
    const sv = mx === 0 ? 0 : (mx - mn) / mx;
    satHist[Math.min(100, Math.round(sv * 100))]++;

    if (sv < 0.10) {
      unsaturated++;
    } else {
      const delta = mx - mn;
      let hv = 0;
      if      (mx === rn) hv = ((gn - bn) / delta + 6) % 6;
      else if (mx === gn) hv = (bn - rn) / delta + 2;
      else                hv = (rn - gn) / delta + 4;
      hueHist[Math.min(359, Math.round(hv * 60))]++;
    }
  }

  // ── luminance statistics ──────────────────────────────────────────────────
  const p1  = histPct(lumHist, total,  1);
  const p5  = histPct(lumHist, total,  5);
  const p25 = histPct(lumHist, total, 25);
  const p50 = histPct(lumHist, total, 50);
  const p75 = histPct(lumHist, total, 75);
  const p95 = histPct(lumHist, total, 95);
  const p99 = histPct(lumHist, total, 99);

  let lumWsum = 0;
  for (let i = 0; i < 256; i++) lumWsum += i * lumHist[i];
  const lumMean = lumWsum / total;

  let lumSumSq = 0;
  for (let i = 0; i < 256; i++) lumSumSq += (i - lumMean) ** 2 * lumHist[i];
  const lumStd = Math.sqrt(lumSumSq / total);

  const dynamicRangeStops = Math.log2(Math.max(p99, 1) / Math.max(p1, 1));

  // ── saturation statistics ─────────────────────────────────────────────────
  let satWsum = 0;
  for (let i = 0; i <= 100; i++) satWsum += satHist[i] * i;
  const satMean = satWsum / total;
  const satMed  = histPct(satHist, total, 50);
  const satP95  = histPct(satHist, total, 95);

  // ── hue distribution (8 LR-aligned buckets) ───────────────────────────────
  const hb: Record<string, number> = {
    red:0, orange:0, yellow:0, green:0, aqua:0, blue:0, purple:0, magenta:0
  };
  for (let hv = 0; hv < 360; hv++) {
    const c = hueHist[hv]; if (!c) continue;
    if      (hv >= 345 || hv <  15) hb.red     += c;
    else if (hv <  45)              hb.orange   += c;
    else if (hv <  75)              hb.yellow   += c;
    else if (hv < 165)              hb.green    += c;
    else if (hv < 195)              hb.aqua     += c;
    else if (hv < 255)              hb.blue     += c;
    else if (hv < 285)              hb.purple   += c;
    else                            hb.magenta  += c;
  }
  const satTotal = total - unsaturated;
  const hueKeys = ["red","orange","yellow","green","aqua","blue","purple","magenta"] as const;
  const huePct = Object.fromEntries(
    hueKeys.map(k => [k, satTotal > 0
      ? parseFloat(((hb[k] / satTotal) * 100).toFixed(1)) : 0])
  ) as Record<typeof hueKeys[number], number>;

  const hueDistribution: HueDist = {
    ...huePct,
    unsaturatedPct: parseFloat(((unsaturated / total) * 100).toFixed(1)),
    dominant: hueKeys.filter(k => huePct[k] > 5).sort((a, b) => huePct[b] - huePct[a])
  };

  // ── tonal clusters (2nd pass, split at p25 / p75) ────────────────────────
  let dR=0,dG=0,dB=0,dL=0,dN=0;
  let mR=0,mG=0,mB=0,mL=0,mN=0;
  let bR=0,bG=0,bB=0,bL=0,bN=0;

  for (let i = 0; i < total; i++) {
    const r = px[i * ch], g = px[i * ch + 1], b = px[i * ch + 2];
    const lum = Math.min(255, Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b));
    if      (lum < p25) { dR+=r; dG+=g; dB+=b; dL+=lum; dN++; }
    else if (lum < p75) { mR+=r; mG+=g; mB+=b; mL+=lum; mN++; }
    else                { bR+=r; bG+=g; bB+=b; bL+=lum; bN++; }
  }

  const mkCluster = (r:number,g:number,b:number,l:number,n:number): TonalCluster => ({
    pctOfPixels: Math.round(n / total * 100),
    r: Math.round(r/(n||1)), g: Math.round(g/(n||1)), b: Math.round(b/(n||1)),
    meanLum: Math.round(l/(n||1)),
    bMinusR: Math.round((b - r)/(n||1))
  });
  const dark   = mkCluster(dR,dG,dB,dL,dN);
  const mid    = mkCluster(mR,mG,mB,mL,mN);
  const bright = mkCluster(bR,bG,bB,bL,bN);

  // ── spatial ───────────────────────────────────────────────────────────────
  const thirds = [0,1,2].map(row => Math.round(
    (gridLum[row*3]+gridLum[row*3+1]+gridLum[row*3+2]) /
    Math.max(1, gridN[row*3]+gridN[row*3+1]+gridN[row*3+2])
  ));
  const grid3x3 = [0,1,2].map(row =>
    [0,1,2].map(col => Math.round(gridLum[row*3+col] / Math.max(1, gridN[row*3+col])))
  );

  // ── assemble result ───────────────────────────────────────────────────────
  return {
    source,
    dimensions: { width: w, height: h },
    luminance: {
      mean: Math.round(lumMean), std: Math.round(lumStd),
      p1, p5, p25, p50, p75, p95, p99,
      dynamicRangeStops: parseFloat(dynamicRangeStops.toFixed(2))
    },
    clipping: {
      highlightsClippedPct: parseFloat(((hlClip/total)*100).toFixed(2)),
      shadowsClippedPct:    parseFloat(((shClip/total)*100).toFixed(2)),
      highlightsWarnPct:    parseFloat(((hlWarn/total)*100).toFixed(2)),
      shadowsWarnPct:       parseFloat(((shWarn/total)*100).toFixed(2)),
    },
    tonalDistribution: {
      blacks:     parseFloat(((zoneCnt[0]/total)*100).toFixed(1)),
      shadows:    parseFloat(((zoneCnt[1]/total)*100).toFixed(1)),
      darkMids:   parseFloat(((zoneCnt[2]/total)*100).toFixed(1)),
      lightMids:  parseFloat(((zoneCnt[3]/total)*100).toFixed(1)),
      highlights: parseFloat(((zoneCnt[4]/total)*100).toFixed(1)),
      whites:     parseFloat(((zoneCnt[5]/total)*100).toFixed(1)),
    },
    tonalClusters: {
      dark, mid, bright,
      tempSpread: bright.bMinusR - dark.bMinusR
    },
    spatial: { thirds, grid3x3 },
    color: {
      means:   { r: Math.round(rSum/total), g: Math.round(gSum/total), b: Math.round(bSum/total) },
      medians: {
        r: histPct(rHist, total, 50),
        g: histPct(gHist, total, 50),
        b: histPct(bHist, total, 50),
      },
      bMinusR: Math.round((bSum - rSum) / total),
      gMinusM: Math.round((gSum * 2 - rSum - bSum) / (2 * total)),
      saturation: {
        mean:   parseFloat(satMean.toFixed(1)),
        median: satMed,
        p95:    satP95,
        isMonochromatic: satMed < 25
      },
      hueDistribution
    }
  };
}
