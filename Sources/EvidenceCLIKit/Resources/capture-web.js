#!/usr/bin/env node
// Playwright web capture script for `evidence capture-web`.
//
// Usage:
//   node capture-web.js <url> <viewportSpec> <fullPage> <waitUntil> <outputPath>
//
//   url          — The page URL to capture (e.g. "https://example.com")
//   viewportSpec — Width x height string (e.g. "1440x900")
//   fullPage     — "true" | "false"
//   waitUntil    — "networkidle" | "load" | "domcontentloaded"
//   outputPath   — Absolute path for the output PNG
//
// Exits 0 on success, 1 on any error (message on stderr).

'use strict';

const [,, url, viewportSpec, fullPageStr, waitUntil, outputPath] = process.argv;

if (!url || !viewportSpec || !fullPageStr || !waitUntil || !outputPath) {
  process.stderr.write(
    'Usage: node capture-web.js <url> <viewportSpec> <fullPage> <waitUntil> <outputPath>\n'
  );
  process.exit(1);
}

const [widthStr, heightStr] = viewportSpec.split('x');
const width = parseInt(widthStr, 10);
const height = parseInt(heightStr, 10);

if (isNaN(width) || isNaN(height) || width <= 0 || height <= 0) {
  process.stderr.write(`Invalid viewport spec: "${viewportSpec}". Expected format: WxH (e.g. "1440x900").\n`);
  process.exit(1);
}

const fullPage = fullPageStr === 'true';

// Map Playwright waitUntil values: "networkidle" maps to "networkidle" in
// Playwright (it waits for no network connections for 500ms).
const validWaitUntil = ['networkidle', 'load', 'domcontentloaded'];
if (!validWaitUntil.includes(waitUntil)) {
  process.stderr.write(`Invalid waitUntil value: "${waitUntil}". Accepted: ${validWaitUntil.join(', ')}.\n`);
  process.exit(1);
}

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  process.stderr.write(
    'Playwright is not installed. Install it with: npm install playwright\n' +
    `Error: ${e.message}\n`
  );
  process.exit(1);
}

(async () => {
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    // Use setViewportSize — do NOT use browser window resize (unreliable).
    await page.setViewportSize({ width, height });

    await page.goto(url, { waitUntil });

    await page.screenshot({
      path: outputPath,
      fullPage,
      type: 'png',
    });

    process.stdout.write(`Captured ${viewportSpec} screenshot at ${outputPath}\n`);
  } catch (e) {
    process.stderr.write(`Screenshot capture failed: ${e.message}\n`);
    process.exit(1);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
})();
