// functions/getDominantColor.js
import {createRequire} from 'module';
const require = createRequire(import.meta.url);

// 1) sharp for cropping
const sharp = require('sharp');

// 2) node-vibrant CJS build → grab the Vibrant class
const VibrantMod = require('node-vibrant/node');
const Vibrant = VibrantMod.Vibrant || VibrantMod.default || VibrantMod;

/**
 * Extracts the dominant color from the *edges* of the image.
 * @param {string} filePath - local path to the image
 * @return {Promise<number>} 32-bit ARGB color integer
 */
export async function getDominantColor(filePath) {
  // --- 1) get dimensions & compute border thickness
  const {width: w, height: h} = await sharp(filePath).metadata();
  const thickness = Math.floor(Math.min(w, h) * 0.10);

  // --- 2) crop each edge strip into a Buffer
  const regions = await Promise.all([
    // top
    sharp(filePath).extract({left: 0, top: 0, width: w, height: thickness}).toBuffer(),
    // bottom
    sharp(filePath).extract({left: 0, top: h - thickness, width: w, height: thickness}).toBuffer(),
    // left
    sharp(filePath).extract({left: 0, top: 0, width: thickness, height: h}).toBuffer(),
    // right
    sharp(filePath).extract({left: w - thickness, top: 0, width: thickness, height: h}).toBuffer(),
  ]);

  // --- 3) run Vibrant on each strip, collect all swatches + populations
  const allEntries = [];
  for (const buf of regions) {
    const palette = await Vibrant.from(buf)
      .maxColorCount(64)
      .quality(1)
      .getPalette();

    for (const swatch of Object.values(palette)) {
      if (!swatch) continue;
      const pop = typeof swatch.getPopulation === 'function' ?
        swatch.getPopulation() :
        swatch.population || 0;
      allEntries.push({swatch, population: pop});
    }
  }

  if (allEntries.length === 0) {
    throw new Error('No swatches found in any border region');
  }

  // --- 4) pick the swatch with the highest population
  const best = allEntries.reduce((a, b) =>
    b.population > a.population ? b : a,
  ).swatch;

  // --- 5) extract RGB and pack into ARGB32
  const [r, g, b] = typeof best.getRgb === 'function' ?
    best.getRgb() :
    best.rgb;
  return ((0xff << 24) | (r << 16) | (g << 8) | b) >>> 0;
}
