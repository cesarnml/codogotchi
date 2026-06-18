#!/usr/bin/env node

const CANONICAL_KEYS = {
  green: "#00B140",
  blue: "#0047BB",
  magenta: "#FF00FF",
};

const PRESETS = {
  balanced: {
    colorSpace: "hsv",
    tolerance: 0.21,
    smoothness: 0.15,
    spill: 0.21,
  },
  preserveDetail: {
    colorSpace: "hsv",
    tolerance: 0.18,
    smoothness: 0.2,
    spill: 0.16,
  },
  strongSpill: {
    colorSpace: "yuv",
    tolerance: 0.24,
    smoothness: 0.13,
    spill: 0.3,
  },
};

function hexToRgb(hex) {
  const shorthandRegex = /^#?([a-f\d])([a-f\d])([a-f\d])$/i;
  const fullHex = hex.replace(
    shorthandRegex,
    (_, r, g, b) => r + r + g + g + b + b,
  );
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(fullHex);
  return result
    ? {
        r: Number.parseInt(result[1], 16),
        g: Number.parseInt(result[2], 16),
        b: Number.parseInt(result[3], 16),
      }
    : { r: 0, g: 177, b: 64 };
}

function rgbToYuv(r, g, b) {
  const rNorm = r / 255;
  const gNorm = g / 255;
  const bNorm = b / 255;
  const y = 0.299 * rNorm + 0.587 * gNorm + 0.114 * bNorm;
  const u = -0.14713 * rNorm - 0.28886 * gNorm + 0.436 * bNorm;
  const v = 0.615 * rNorm - 0.51499 * gNorm - 0.10001 * bNorm;
  return { y, u, v };
}

function rgbToHsv(r, g, b) {
  const rNorm = r / 255;
  const gNorm = g / 255;
  const bNorm = b / 255;
  const max = Math.max(rNorm, gNorm, bNorm);
  const min = Math.min(rNorm, gNorm, bNorm);
  const delta = max - min;

  let h = 0;
  if (delta > 0) {
    if (max === rNorm) {
      h = 60 * (((gNorm - bNorm) / delta) % 6);
    } else if (max === gNorm) {
      h = 60 * ((bNorm - rNorm) / delta + 2);
    } else {
      h = 60 * ((rNorm - gNorm) / delta + 4);
    }
  }
  if (h < 0) h += 360;

  const s = max === 0 ? 0 : delta / max;
  const v = max;
  return { h, s, v };
}

function applyChromaKey(sourceData, keyColorHex, preset) {
  const src = sourceData;
  const dst = new Uint8ClampedArray(src.length);
  const targetRgb = hexToRgb(keyColorHex);
  const targetYuv = rgbToYuv(targetRgb.r, targetRgb.g, targetRgb.b);
  const targetHsv = rgbToHsv(targetRgb.r, targetRgb.g, targetRgb.b);

  for (let i = 0; i < src.length; i += 4) {
    let r = src[i];
    let g = src[i + 1];
    let b = src[i + 2];
    const a = src[i + 3];

    if (a === 0) {
      continue;
    }

    if (preset.spill > 0) {
      let despilledR = r;
      let despilledG = g;
      let despilledB = b;

      if (targetRgb.g >= targetRgb.r && targetRgb.g >= targetRgb.b) {
        const edge = (r + b) / 2;
        if (g > edge) despilledG = edge;
      } else if (targetRgb.b >= targetRgb.r && targetRgb.b >= targetRgb.g) {
        const edge = (r + g) / 2;
        if (b > edge) despilledB = edge;
      } else {
        const edge = (g + b) / 2;
        if (r > edge) despilledR = edge;
      }

      r = Math.round(r * (1 - preset.spill) + despilledR * preset.spill);
      g = Math.round(g * (1 - preset.spill) + despilledG * preset.spill);
      b = Math.round(b * (1 - preset.spill) + despilledB * preset.spill);
    }

    let dist = 0;
    if (preset.colorSpace === "yuv") {
      const pixelYuv = rgbToYuv(r, g, b);
      const uDiff = pixelYuv.u - targetYuv.u;
      const vDiff = pixelYuv.v - targetYuv.v;
      dist = Math.min(Math.sqrt(uDiff * uDiff + vDiff * vDiff) / 0.75, 1.0);
    } else if (preset.colorSpace === "rgb") {
      const rDiff = (r - targetRgb.r) / 255;
      const gDiff = (g - targetRgb.g) / 255;
      const bDiff = (b - targetRgb.b) / 255;
      dist =
        Math.sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff) / Math.sqrt(3);
    } else {
      const pixelHsv = rgbToHsv(r, g, b);
      let hDiff = Math.abs(pixelHsv.h - targetHsv.h);
      if (hDiff > 180) hDiff = 360 - hDiff;
      const normHDiff = hDiff / 180;
      const sDiff = Math.abs(pixelHsv.s - targetHsv.s);
      const vDiff = Math.abs(pixelHsv.v - targetHsv.v);
      dist = normHDiff * 0.75 + sDiff * 0.2 + vDiff * 0.05;
    }

    let computedAlpha = 1;
    const lowBoundary = preset.tolerance * 0.85;
    const rampWidth = preset.smoothness * 0.45 + 0.005;
    if (dist <= lowBoundary) {
      computedAlpha = 0;
    } else if (dist < lowBoundary + rampWidth) {
      const k = (dist - lowBoundary) / rampWidth;
      computedAlpha = Math.sin((k * Math.PI) / 2);
    }

    computedAlpha = Math.max(0, Math.min(1, computedAlpha));
    const finalAlpha = Math.round(computedAlpha * (a / 255) * 255);
    dst[i] = r;
    dst[i + 1] = g;
    dst[i + 2] = b;
    dst[i + 3] = finalAlpha;
  }

  for (let i = 0; i < dst.length; i += 4) {
    if (dst[i + 3] === 0) {
      dst[i] = 0;
      dst[i + 1] = 0;
      dst[i + 2] = 0;
    }
  }

  return dst;
}

function parseArgs(argv) {
  const args = { preset: "balanced", keyColor: CANONICAL_KEYS.green };
  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--preset") args.preset = argv[++i];
    else if (arg === "--key-color") args.keyColor = argv[++i];
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Object.values(CANONICAL_KEYS).includes(args.keyColor.toUpperCase())) {
    throw new Error(
      `--key-color must be one of ${Object.values(CANONICAL_KEYS).join(", ")}`,
    );
  }
  if (!(args.preset in PRESETS)) {
    throw new Error(
      `--preset must be one of ${Object.keys(PRESETS).join(", ")}`,
    );
  }
  return args;
}

async function readStdin() {
  let data = "";
  for await (const chunk of process.stdin) data += chunk;
  return data;
}

async function main() {
  const args = parseArgs(process.argv);
  const raw = await readStdin();
  const payload = JSON.parse(raw);
  const rgba = new Uint8ClampedArray(Buffer.from(payload.rgbaBase64, "base64"));
  const keyed = applyChromaKey(rgba, args.keyColor, PRESETS[args.preset]);
  process.stdout.write(
    JSON.stringify({
      width: payload.width,
      height: payload.height,
      rgbaBase64: Buffer.from(keyed).toString("base64"),
      keyColor: args.keyColor.toUpperCase(),
      preset: args.preset,
      ...PRESETS[args.preset],
    }),
  );
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
