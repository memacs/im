#!/usr/bin/env node
/**
 * 将 public/intro/index.html 各屏截图为 GIF（默认每帧 2 秒）。
 *
 * 用法：npm run intro:gif
 * 产出：public/intro/intro.gif
 */
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { join, extname } from "node:path";
import { fileURLToPath } from "node:url";
import { writeFileSync } from "node:fs";
import gifenc from "gifenc";
import { PNG } from "pngjs";
import { chromium } from "playwright";

const { GIFEncoder, quantize, applyPalette } = gifenc;

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const ROOT = join(__dirname, "..");
const INTRO_DIR = join(ROOT, "public", "intro");
const OUT_GIF = join(INTRO_DIR, "intro.gif");

const VIEWPORT = { width: 1280, height: 720 };
const FRAME_DELAY_MS = 2000; // gifenc delay 单位为毫秒
const SCENE_COUNT = 11;
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css",
  ".js": "application/javascript",
  ".png": "image/png",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

function startStaticServer(dir, port = 0) {
  return new Promise((resolve) => {
    const server = createServer(async (req, res) => {
      const path = (req.url ?? "/").split("?")[0];
      const file = join(dir, path === "/" ? "index.html" : path);
      try {
        const body = await readFile(file);
        res.writeHead(200, {
          "Content-Type": MIME[extname(file)] ?? "application/octet-stream",
        });
        res.end(body);
      } catch {
        res.writeHead(404).end("Not found");
      }
    });
    server.listen(port, "127.0.0.1", () => {
      const addr = server.address();
      const p = typeof addr === "object" && addr ? addr.port : port;
      resolve({ server, url: `http://127.0.0.1:${p}` });
    });
  });
}

async function captureFrames(pageUrl) {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: VIEWPORT });

  await page.addInitScript(() => {
    window.__INTRO_CAPTURE__ = true;
  });

  await page.goto(`${pageUrl}/intro/index.html?capture=1`, {
    waitUntil: "networkidle",
  });

  await page.addStyleTag({
    content: `
      .controls, .progress-nav, .scroll-hint { display: none !important; }
    `,
  });

  const frames = [];

  for (let i = 0; i < SCENE_COUNT; i++) {
    await page.locator(`#s${i}`).scrollIntoViewIfNeeded();
    await page.waitForTimeout(900);
    const png = await page.screenshot({ type: "png" });
    frames.push(PNG.sync.read(png));
  }

  await browser.close();
  return frames;
}

function encodeGif(frames) {
  const encoder = GIFEncoder();
  let width = 0;
  let height = 0;

  for (const frame of frames) {
    width = frame.width;
    height = frame.height;
    const rgba = frame.data;
    const palette = quantize(rgba, 256);
    const index = applyPalette(rgba, palette);
    encoder.writeFrame(index, width, height, {
      palette,
      delay: FRAME_DELAY_MS,
    });
  }

  encoder.finish();
  return encoder.bytes();
}

async function main() {
  console.log("启动静态服务…");
  const { server, url } = await startStaticServer(join(ROOT, "public"));

  try {
    console.log(`截图 ${SCENE_COUNT} 屏（${FRAME_DELAY_MS / 1000}s/帧）…`);
    const frames = await captureFrames(url);
    console.log("编码 GIF…");
    const bytes = encodeGif(frames);
    writeFileSync(OUT_GIF, Buffer.from(bytes));
    const kb = (bytes.length / 1024).toFixed(1);
    console.log(`已写入 ${OUT_GIF}（${kb} KB，${SCENE_COUNT} 帧 × 2s ≈ ${SCENE_COUNT * 2}s）`);
  } finally {
    server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
