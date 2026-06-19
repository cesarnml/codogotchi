/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export interface RGB {
  r: number;
  g: number;
  b: number;
}

export interface YUV {
  y: number;
  u: number;
  v: number;
}

export interface HSV {
  h: number; // 0 to 360
  s: number; // 0 to 1
  v: number; // 0 to 1
}

export function hexToRgb(hex: string): RGB {
  const shorthandRegex = /^#?([a-f\d])([a-f\d])([a-f\d])$/i;
  const fullHex = hex.replace(shorthandRegex, (_, r, g, b) => r + r + g + g + b + b);
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(fullHex);
  return result ? {
    r: parseInt(result[1], 16),
    g: parseInt(result[2], 16),
    b: parseInt(result[3], 16)
  } : { r: 0, g: 255, b: 0 };
}

export function rgbToHex(r: number, g: number, b: number): string {
  const clamp = (val: number) => Math.max(0, Math.min(255, Math.round(val)));
  return '#' + [clamp(r), clamp(g), clamp(b)].map(x => {
    const hex = x.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }).join('');
}

export function rgbToYuv(r: number, g: number, b: number): YUV {
  // Re-scale to [0, 1] for simpler weightings
  const rNorm = r / 255;
  const gNorm = g / 255;
  const bNorm = b / 255;
  
  // Standard ITU-R BT.601 conversion formula weights
  const y = 0.299 * rNorm + 0.587 * gNorm + 0.114 * bNorm;
  const u = -0.14713 * rNorm - 0.28886 * gNorm + 0.436 * bNorm;
  const v = 0.615 * rNorm - 0.51499 * gNorm - 0.10001 * bNorm;
  
  return { y, u, v };
}

export function rgbToHsv(r: number, g: number, b: number): HSV {
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
      h = 60 * (((bNorm - rNorm) / delta) + 2);
    } else {
      h = 60 * (((rNorm - gNorm) / delta) + 4);
    }
  }
  if (h < 0) h += 360;
  
  const s = max === 0 ? 0 : delta / max;
  const v = max;
  return { h, s, v };
}

/**
 * Key pixels on an ImageData object
 */
export function applyChromaKey(
  sourceData: ImageData,
  targetData: ImageData,
  keyColorHex: string,
  tolerance: number, // 0 to 1
  smoothness: number, // 0 to 1
  spill: number, // 0 to 1
  colorSpace: 'yuv' | 'rgb' | 'hsv',
  maskOnly: boolean
) {
  const src = sourceData.data;
  const dst = targetData.data;
  const len = src.length;
  
  const targetRgb = hexToRgb(keyColorHex);
  const targetYuv = rgbToYuv(targetRgb.r, targetRgb.g, targetRgb.b);
  const targetHsv = rgbToHsv(targetRgb.r, targetRgb.g, targetRgb.b);
  
  for (let i = 0; i < len; i += 4) {
    let r = src[i];
    let g = src[i + 1];
    let b = src[i + 2];
    const a = src[i + 3];
    
    if (a === 0) {
      dst[i] = 0;
      dst[i + 1] = 0;
      dst[i + 2] = 0;
      dst[i + 3] = 0;
      continue;
    }
    
    // 1. SPILL SUPPRESSION (Applied to RGB before distance calculation or combined)
    if (spill > 0) {
      let despilledR = r;
      let despilledG = g;
      let despilledB = b;
      
      // Determine dominant spectrum of the targeted key color
      if (targetRgb.g >= targetRgb.r && targetRgb.g >= targetRgb.b) {
        // Green spill suppression: clamp Green to the average of Red and Blue
        const edge = (r + b) / 2.0;
        if (g > edge) {
          despilledG = edge;
        }
      } else if (targetRgb.b >= targetRgb.r && targetRgb.b >= targetRgb.g) {
        // Blue spill suppression: clamp Blue to average of Red and Green
        const edge = (r + g) / 2.0;
        if (b > edge) {
          despilledB = edge;
        }
      } else if (targetRgb.r >= targetRgb.g && targetRgb.r >= targetRgb.b) {
        // Red spill suppression: clamp Red to average of Green and Blue
        const edge = (g + b) / 2.0;
        if (r > edge) {
          despilledR = edge;
        }
      }
      
      // Blend despilled color based on the slider ratio
      r = Math.round(r * (1 - spill) + despilledR * spill);
      g = Math.round(g * (1 - spill) + despilledG * spill);
      b = Math.round(b * (1 - spill) + despilledB * spill);
    }
    
    // 2. CHROMA KEY DISTANCE & ALPHA
    let dist = 0;
    
    if (colorSpace === 'yuv') {
      const pixelYuv = rgbToYuv(r, g, b);
      // Chrominance distance ignores brightness variance (Y), isolating color difference
      const uDiff = pixelYuv.u - targetYuv.u;
      const vDiff = pixelYuv.v - targetYuv.v;
      dist = Math.sqrt(uDiff * uDiff + vDiff * vDiff);
      
      // Chrominance distance is normally smaller. Max chrominance distance is approx 0.8
      // Normalize to 0-1
      dist = Math.min(dist / 0.75, 1.0);
    } else if (colorSpace === 'rgb') {
      const rDiff = (r - targetRgb.r) / 255;
      const gDiff = (g - targetRgb.g) / 255;
      const bDiff = (b - targetRgb.b) / 255;
      dist = Math.sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff) / Math.sqrt(3);
    } else { // HSV space
      const pixelHsv = rgbToHsv(r, g, b);
      let hDiff = Math.abs(pixelHsv.h - targetHsv.h);
      if (hDiff > 180) hDiff = 360 - hDiff;
      const normHDiff = hDiff / 180; // [0, 1]
      
      const sDiff = Math.abs(pixelHsv.s - targetHsv.s);
      const vDiff = Math.abs(pixelHsv.v - targetHsv.v);
      
      // Hue accounts for 75% of color classification, Saturation for 20%, Value for 5%
      dist = normHDiff * 0.75 + sDiff * 0.20 + vDiff * 0.05;
    }
    
    // Calculate final alpha transparency based on similarity tolerance and edge smoothness
    let computedAlpha = 1.0;
    
    // Tolerance acts as key threshold
    const lowBoundary = tolerance * 0.85; // slightly lowered for smoother dynamic range
    // Smoothness represents width of transition ramp
    const rampWidth = smoothness * 0.45 + 0.005; // tiny epsilon to avoid division by zero
    
    if (dist <= lowBoundary) {
      computedAlpha = 0.0;
    } else if (dist >= lowBoundary + rampWidth) {
      computedAlpha = 1.0;
    } else {
      // Soft transition interpolation
      const k = (dist - lowBoundary) / rampWidth;
      // Sinusoidal easing curve for extra elegance
      computedAlpha = Math.sin(k * Math.PI / 2);
    }
    
    // Keep alpha bounded
    computedAlpha = Math.max(0, Math.min(1, computedAlpha));
    const finalAlpha = Math.round(computedAlpha * (a / 255) * 255);
    
    // 3. APPLY OUTPUT
    if (maskOnly) {
      // White for opaque pixels, black for transparent pixels (visualizing the key mask)
      const maskVal = Math.round(computedAlpha * 255);
      dst[i] = maskVal;
      dst[i + 1] = maskVal;
      dst[i + 2] = maskVal;
      dst[i + 3] = 255;
    } else {
      dst[i] = r;
      dst[i + 1] = g;
      dst[i + 2] = b;
      dst[i + 3] = finalAlpha;
    }
  }
}
