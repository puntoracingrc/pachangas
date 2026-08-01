import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { platform } from "node:os";
import { setTimeout as delay } from "node:timers/promises";

const baseUrl = process.env.COMPAT_BASE_URL ?? "http://127.0.0.1:3000";
const chromePath = process.env.CHROME_PATH ?? findChromePath();
const viewports = [
  { expectTab: true, height: 780, label: "small phone portrait", tab: "partido", width: 360 },
  { expectTab: true, height: 375, label: "small phone landscape", tab: "partido", width: 667 },
  { expectTab: true, height: 390, label: "large phone game landscape", tab: "partido", width: 844 },
  { expectTab: true, height: 720, label: "foldable portrait-like window", tab: "equipo", width: 717 },
  { height: 600, label: "tablet split or small landscape tablet", tab: "mercado", width: 1024 },
  { height: 800, label: "large tablet landscape", tab: "perfil", width: 1280 },
  { height: 950, label: "desktop or ChromeOS wide window", tab: "inicio", width: 1700 },
];

function findChromePath() {
  const candidates = platform() === "darwin"
    ? [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
      ]
    : [
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
      ];

  return candidates.find((candidate) => existsSync(candidate));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForJson(url, attempts = 40) {
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) return response.json();
      lastError = new Error(`${response.status} ${response.statusText}`);
    } catch (error) {
      lastError = error;
    }
    await delay(150);
  }
  throw lastError ?? new Error(`No response from ${url}`);
}

function chromeArgs(userDataDir, port) {
  return [
    "--headless=new",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--disable-extensions",
    "--no-first-run",
    "--no-default-browser-check",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    "about:blank",
  ];
}

function connectSocket(url) {
  const socket = new WebSocket(url);
  const pending = new Map();
  let nextId = 1;

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data));
    if (!message.id || !pending.has(message.id)) return;
    const { reject, resolve } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result);
  });

  return new Promise((resolve, reject) => {
    socket.addEventListener("open", () => {
      resolve({
        close: () => socket.close(),
        send(method, params = {}) {
          const id = nextId;
          nextId += 1;
          socket.send(JSON.stringify({ id, method, params }));
          return new Promise((sendResolve, sendReject) => {
            pending.set(id, { reject: sendReject, resolve: sendResolve });
          });
        },
      });
    }, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
}

async function openPage(port) {
  const target = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" }).then((response) => response.json());
  return connectSocket(target.webSocketDebuggerUrl);
}

function routeFor(tab) {
  const url = new URL(baseUrl);
  if (tab !== "inicio") url.searchParams.set("mobile", tab);
  return url.toString();
}

async function evaluate(client, expression) {
  const result = await client.send("Runtime.evaluate", {
    awaitPromise: true,
    expression,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.text ?? "Evaluation failed");
  }
  return result.result.value;
}

async function runViewport(client, viewport) {
  await client.send("Emulation.setDeviceMetricsOverride", {
    deviceScaleFactor: 2,
    height: viewport.height,
    mobile: viewport.width < 900,
    width: viewport.width,
  });
  await client.send("Page.navigate", { url: routeFor(viewport.tab) });
  await delay(900);

  const metrics = await evaluate(client, `(() => {
    const doc = document.documentElement;
    const body = document.body;
    const text = body.innerText || "";
    const main = document.querySelector("main[data-mobile-tab]");
    const nav = document.querySelector(".mobile-app-nav");
    const overflow = Math.max(doc.scrollWidth, body.scrollWidth) - Math.max(doc.clientWidth, window.innerWidth);
    return {
      heightClass: doc.dataset.windowHeightClass || "",
      hasContent: text.includes("Pachangas IQ") || text.includes("Partido") || text.includes("Mercado"),
      hasMain: Boolean(main),
      hasNav: Boolean(nav),
      overflow,
      tab: main?.dataset.mobileTab || "",
      widthClass: doc.dataset.windowWidthClass || ""
    };
  })()`);

  assert(metrics.hasContent, `${viewport.label}: missing content`);
  assert(metrics.hasMain, `${viewport.label}: missing mobile main shell`);
  assert(metrics.hasNav, `${viewport.label}: missing app navigation`);
  assert(metrics.overflow <= 2, `${viewport.label}: horizontal overflow ${metrics.overflow}px`);
  assert(metrics.widthClass, `${viewport.label}: missing width size class`);
  assert(metrics.heightClass, `${viewport.label}: missing height size class`);
  if (viewport.expectTab) {
    assert(metrics.tab === viewport.tab, `${viewport.label}: expected tab ${viewport.tab}, got ${metrics.tab}`);
  }

  return { ...viewport, ...metrics };
}

async function main() {
  if (!chromePath) {
    throw new Error("Chrome/Chromium not found. Set CHROME_PATH to run adaptive browser smoke tests.");
  }

  const health = await fetch(baseUrl).catch(() => undefined);
  assert(health?.ok, `App is not reachable at ${baseUrl}. Start it first, then run npm run compat:browser.`);

  const manifest = await fetch(new URL("/manifest.webmanifest", baseUrl)).then((response) => response.json());
  assert(manifest.orientation === "any", "manifest must not lock orientation");
  assert(Array.isArray(manifest.display_override), "manifest missing display_override");
  assert(manifest.icons?.some((icon) => icon.purpose === "monochrome"), "manifest missing monochrome icon");

  const port = 9339;
  const browser = spawn(chromePath, chromeArgs(`/tmp/pachangas-adaptive-chrome-${process.pid}`, port), {
    stdio: "ignore",
  });

  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    const client = await openPage(port);
    await client.send("Page.enable");
    await client.send("Runtime.enable");

    const results = [];
    for (const viewport of viewports) {
      results.push(await runViewport(client, viewport));
    }
    client.close();
    console.table(results.map(({ height, heightClass, label, overflow, tab, width, widthClass }) => ({
      viewport: `${width}x${height}`,
      label,
      tab,
      widthClass,
      heightClass,
      overflow,
    })));
  } finally {
    browser.kill();
  }
}

await main();
