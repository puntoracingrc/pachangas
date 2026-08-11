import { spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { platform } from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const baseUrl = process.env.VISUAL_AUDIT_BASE_URL ?? "http://127.0.0.1:3000";
const label = (process.env.VISUAL_AUDIT_LABEL ?? "current").replace(/[^a-z0-9_-]/gi, "-");
const outputRoot = path.resolve(process.env.VISUAL_AUDIT_OUTPUT ?? "artifacts/visual-audit-v1", label);
const chromePath = process.env.CHROME_PATH ?? findChromePath();
const captureScreenshots = process.env.VISUAL_AUDIT_SCREENSHOTS !== "0";

const viewports = [
  { key: "desktop", width: 1440, height: 900 },
  { key: "portrait", width: 390, height: 844 },
  { key: "landscape", width: 844, height: 390 },
];

const surfaces = [
  { key: "demo-inicio-admin", path: "/?demo=1&mobile=inicio", userMode: "demo-admin", capture: true },
  { key: "demo-inicio-player", path: "/?demo=1&mobile=inicio&qaPlayer=1", userMode: "demo-player", capture: false },
  { key: "demo-partido", path: "/?demo=1&mobile=partido", userMode: "demo-admin", capture: true },
  { key: "demo-mercado", path: "/?demo=1&mobile=mercado", userMode: "demo-admin", capture: false },
  { key: "demo-equipo", path: "/?demo=1&mobile=equipo", userMode: "demo-admin", capture: false },
  { key: "demo-perfil", path: "/?demo=1&mobile=perfil", userMode: "demo-admin", capture: false },
  { key: "mercado", path: "/mercado", userMode: "visitor", capture: true },
  { key: "personalizar-carta", path: "/personalizar-carta", userMode: "visitor", capture: true },
  { key: "equipo-identidad", path: "/equipo/identidad", userMode: "visitor-no-team", capture: true },
  { key: "avisos", path: "/perfil/avisos", userMode: "visitor", capture: true },
  { key: "conducta", path: "/perfil/conducta", userMode: "visitor", capture: false },
  { key: "partido-invitado", path: "/partido-invitado", userMode: "visitor", capture: false },
  { key: "invitacion-partido", path: "/invitacion-partido", userMode: "visitor", capture: false },
  { key: "valorar-equipo", path: "/valorar-equipo", userMode: "visitor", capture: false },
  { key: "lab-escudos", path: "/laboratorio-cosmeticos-escudo", userMode: "lab", capture: true },
  { key: "lab-cartas", path: "/laboratorio-cosmeticos-ficha", userMode: "lab", capture: false },
  { key: "lab-rating", path: "/laboratorio-ficha-jugador", userMode: "lab", capture: false },
  { key: "lab-ranking", path: "/laboratorio-ranking-provincial", userMode: "lab", capture: false },
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

async function waitForJson(url, attempts = 60) {
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

function connectSocket(url) {
  const socket = new WebSocket(url);
  const pending = new Map();
  const listeners = new Set();
  let nextId = 1;

  socket.addEventListener("message", (event) => {
    const message = JSON.parse(String(event.data));
    if (message.id && pending.has(message.id)) {
      const { reject, resolve } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
      return;
    }
    for (const listener of listeners) listener(message);
  });

  return new Promise((resolve, reject) => {
    socket.addEventListener("open", () => {
      resolve({
        close: () => socket.close(),
        onEvent(listener) {
          listeners.add(listener);
          return () => listeners.delete(listener);
        },
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
  const target = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })
    .then((response) => response.json());
  return connectSocket(target.webSocketDebuggerUrl);
}

async function evaluate(client, expression) {
  const result = await client.send("Runtime.evaluate", {
    awaitPromise: true,
    expression,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text ?? "Evaluation failed");
  }
  return result.result.value;
}

function auditExpression() {
  return `(() => {
    const doc = document.documentElement;
    const body = document.body;
    const viewport = { width: window.innerWidth, height: window.innerHeight };
    const visible = (element) => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0
        && rect.width > 0 && rect.height > 0;
    };
    const descriptor = (element) => {
      const text = (element.getAttribute("aria-label") || element.textContent || "").trim().replace(/\\s+/g, " ").slice(0, 80);
      return { tag: element.tagName.toLowerCase(), text, className: String(element.className || "").slice(0, 100) };
    };
    const controls = [...document.querySelectorAll("button, a[href], input, select, textarea, [role='button'], [role='tab']")]
      .filter(visible)
      .map((element) => ({ element, rect: element.getBoundingClientRect() }));
    const smallTargets = controls
      .filter(({ element, rect }) => !element.hasAttribute("disabled") && (rect.width < 40 || rect.height < 40))
      .slice(0, 30)
      .map(({ element, rect }) => ({ ...descriptor(element), width: Math.round(rect.width), height: Math.round(rect.height) }));
    const viewportViolations = controls
      .filter(({ element, rect }) => {
        const position = getComputedStyle(element).position;
        return (position === "fixed" || position === "sticky")
          && (rect.left < -2 || rect.right > viewport.width + 2 || rect.top < -2 || rect.bottom > viewport.height + 2);
      })
      .slice(0, 20)
      .map(({ element, rect }) => ({
        ...descriptor(element),
        left: Math.round(rect.left), right: Math.round(rect.right), top: Math.round(rect.top), bottom: Math.round(rect.bottom),
      }));
    const failedImages = [...document.images]
      .filter((image) => image.complete && image.naturalWidth === 0)
      .map((image) => image.currentSrc || image.src || image.alt || "unknown");
    return {
      title: document.title,
      theme: doc.dataset.theme || getComputedStyle(doc).colorScheme || "",
      textLength: (body.innerText || "").trim().length,
      overflowX: Math.max(doc.scrollWidth, body.scrollWidth) - Math.max(doc.clientWidth, window.innerWidth),
      overflowY: Math.max(doc.scrollHeight, body.scrollHeight) - Math.max(doc.clientHeight, window.innerHeight),
      failedImages,
      smallTargets,
      viewportViolations,
      activeElement: descriptor(document.activeElement || body),
    };
  })()`;
}

function markdownReport(results) {
  const rows = results.map((result) => {
    const status = result.navigationError || result.consoleErrors.length || result.failedRequests.length
      || result.metrics.failedImages.length || result.metrics.overflowX > 2 || result.metrics.viewportViolations.length
      ? "REVIEW"
      : "PASS";
    return `| ${result.surface} | ${result.userMode} | ${result.viewport} | ${status} | ${result.metrics.overflowX} | ${result.consoleErrors.length} | ${result.consoleWarnings.length} | ${result.metrics.failedImages.length} | ${result.metrics.smallTargets.length} |`;
  });
  return [
    `# Visual Audit ${label}`,
    "",
    `Base URL: \`${baseUrl}\``,
    "",
    "| Route | User mode | Viewport | Result | Overflow X | Console errors | Warnings | Broken images | Small targets |",
    "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ...rows,
    "",
  ].join("\n");
}

async function main() {
  assert(chromePath, "Chrome/Chromium not found. Set CHROME_PATH to run the visual audit.");
  const health = await fetch(baseUrl).catch(() => undefined);
  assert(health?.ok, `App is not reachable at ${baseUrl}`);

  await mkdir(outputRoot, { recursive: true });
  const port = 9400 + (process.pid % 400);
  const userDataDir = `/tmp/pachangas-visual-audit-${process.pid}`;
  const browser = spawn(chromePath, [
    "--headless=new",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--disable-extensions",
    "--no-first-run",
    "--no-default-browser-check",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${userDataDir}`,
    "about:blank",
  ], { stdio: "ignore" });

  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    const client = await openPage(port);
    await Promise.all([
      client.send("Page.enable"),
      client.send("Runtime.enable"),
      client.send("Network.enable"),
    ]);
    await client.send("Page.addScriptToEvaluateOnNewDocument", {
      source: `if (new URL(location.href).searchParams.has("qaPlayer")) sessionStorage.setItem("pachangas-admin-view-preview", "player"); else sessionStorage.removeItem("pachangas-admin-view-preview");`,
    });

    let consoleErrors = [];
    let consoleWarnings = [];
    let failedRequests = [];
    client.onEvent((message) => {
      if (message.method === "Runtime.consoleAPICalled") {
        const text = (message.params.args ?? []).map((arg) => arg.value ?? arg.description ?? "").join(" ");
        if (message.params.type === "error") consoleErrors.push(text);
        if (message.params.type === "warning" || message.params.type === "warn") consoleWarnings.push(text);
      }
      if (message.method === "Runtime.exceptionThrown") {
        consoleErrors.push(message.params.exceptionDetails?.exception?.description ?? "Uncaught exception");
      }
      if (message.method === "Network.loadingFailed" && !message.params.canceled) {
        failedRequests.push(`${message.params.errorText}: ${message.params.requestId}`);
      }
    });

    const results = [];
    for (const viewport of viewports) {
      await client.send("Emulation.setDeviceMetricsOverride", {
        deviceScaleFactor: 1,
        height: viewport.height,
        mobile: viewport.width < 900,
        width: viewport.width,
      });
      for (const surface of surfaces) {
        consoleErrors = [];
        consoleWarnings = [];
        failedRequests = [];
        let navigationError = "";
        try {
          const url = new URL(surface.path, baseUrl).toString();
          await client.send("Page.navigate", { url });
          await delay(650);
          await evaluate(client, "document.fonts?.ready ?? Promise.resolve()");
        } catch (error) {
          navigationError = error instanceof Error ? error.message : String(error);
        }
        const metrics = await evaluate(client, auditExpression());
        const result = {
          surface: surface.key,
          path: surface.path,
          userMode: surface.userMode,
          viewport: `${viewport.width}x${viewport.height}`,
          metrics,
          consoleErrors: [...new Set(consoleErrors)],
          consoleWarnings: [...new Set(consoleWarnings)],
          failedRequests: [...new Set(failedRequests)],
          navigationError,
        };
        results.push(result);

        if (captureScreenshots && surface.capture) {
          const screenshot = await client.send("Page.captureScreenshot", {
            format: "jpeg",
            fromSurface: true,
            quality: 84,
          });
          await writeFile(
            path.join(outputRoot, `${surface.key}--${viewport.key}.jpg`),
            Buffer.from(screenshot.data, "base64"),
          );
        }
      }
    }

    await writeFile(path.join(outputRoot, "results.json"), `${JSON.stringify(results, null, 2)}\n`);
    await writeFile(path.join(outputRoot, "matrix.md"), markdownReport(results));
    client.close();
    console.log(JSON.stringify({ outputRoot, results: results.length }, null, 2));
  } finally {
    browser.kill();
    await rm(userDataDir, { force: true, recursive: true });
  }
}

await main();
