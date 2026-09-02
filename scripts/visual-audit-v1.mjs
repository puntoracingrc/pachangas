import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { platform } from "node:os";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const baseUrl = process.env.VISUAL_AUDIT_BASE_URL ?? "http://localhost:3000";
const label = (process.env.VISUAL_AUDIT_LABEL ?? "current").replace(/[^a-z0-9_-]/gi, "-");
const outputRoot = path.resolve(process.env.VISUAL_AUDIT_OUTPUT ?? "artifacts/visual-audit-v1", label);
const chromePath = process.env.CHROME_PATH ?? findChromePath();
const captureScreenshots = process.env.VISUAL_AUDIT_SCREENSHOTS !== "0";
const appMode = process.env.VISUAL_AUDIT_APP_MODE === "1";

function requestedKeys(name) {
  return new Set((process.env[name] ?? "").split(",").map((key) => key.trim()).filter(Boolean));
}

const viewports = [
  { key: "desktop", width: 1440, height: 900, capture: true },
  { key: "desktop-wide", width: 1920, height: 1080, capture: true },
  { key: "portrait", width: 390, height: 844, capture: true },
  { key: "portrait-small", width: 360, height: 800, capture: true },
  { key: "landscape-small", width: 667, height: 375, capture: true },
  { key: "landscape-low", width: 740, height: 360, capture: true },
  { key: "landscape", width: 844, height: 390, capture: true },
  { key: "landscape-wide", width: 932, height: 430, capture: true },
  { key: "pwa-portrait", width: 390, height: 844, capture: true, displayMode: "standalone" },
  {
    key: "light-portrait",
    width: 390,
    height: 844,
    capture: false,
    colorScheme: "light",
    surfaceKeys: ["home-visitor", "demo-review", "demo-partido", "demo-retos", "demo-mercado", "demo-equipo", "demo-perfil", "demo-avisos"],
  },
  {
    key: "dark-portrait",
    width: 390,
    height: 844,
    capture: false,
    colorScheme: "dark",
    surfaceKeys: ["home-visitor", "demo-review", "demo-partido", "demo-retos", "demo-mercado", "demo-equipo", "demo-perfil", "demo-avisos"],
  },
  { key: "zoom-125", width: 1152, height: 720, capture: false, surfaceKeys: ["demo-inicio-admin", "mercado", "personalizar-carta", "equipo-identidad"] },
  { key: "zoom-150", width: 960, height: 600, capture: false, surfaceKeys: ["demo-inicio-admin", "mercado", "personalizar-carta", "equipo-identidad"] },
  { key: "zoom-200", width: 720, height: 450, capture: false, surfaceKeys: ["demo-inicio-admin", "mercado", "personalizar-carta", "equipo-identidad"] },
  { key: "reduced-motion", width: 1440, height: 900, capture: false, reducedMotion: true, surfaceKeys: ["home-visitor", "demo-review", "demo-partido", "demo-retos", "demo-mercado", "demo-equipo", "demo-perfil", "demo-avisos", "personalizar-carta"] },
];

const surfaces = [
  { key: "home-visitor", path: "/", userMode: "visitor", capture: true },
  { key: "demo-review", path: "/demo?review=1", userMode: "demo-review", capture: true },
  { key: "demo-inicio-admin", path: "/demo?tab=inicio&perspective=admin", userMode: "demo-admin", capture: true },
  { key: "demo-inicio-player", path: "/demo?tab=inicio&perspective=player", userMode: "demo-player", capture: true },
  { key: "demo-inicio-free-agent", path: "/demo?tab=inicio&perspective=free-agent", userMode: "demo-free-agent", capture: true },
  { key: "demo-campos-team-owner", path: "/demo?tab=campos&perspective=admin", userMode: "demo-team-owner", capture: true },
  { key: "demo-campos-club-desk", path: "/demo?tab=campos&perspective=admin", userMode: "demo-club-booking-manager", clickSelector: "[data-demo-field-operations='v3.4'] button", clickText: "Gestor de reservas", capture: true },
  { key: "demo-campos-organizer", path: "/demo?tab=campos&perspective=admin", userMode: "demo-competition-organizer", clickSelector: "[data-demo-field-operations='v3.4'] button", clickText: "Organizador", capture: false },
  { key: "demo-campos-player", path: "/demo?tab=campos&perspective=player", userMode: "demo-player", clickSelector: "[data-demo-field-operations='v3.4'] button", clickText: "Jugador", capture: false },
  { key: "demo-campos-referee", path: "/demo?tab=campos&perspective=referee", userMode: "demo-referee", clickSelector: "[data-demo-field-operations='v3.4'] button", clickText: "Árbitro", capture: false },
  { key: "demo-campos-platform", path: "/demo?tab=campos&perspective=admin", userMode: "demo-platform-reviewer", clickSelector: "[data-demo-field-operations='v3.4'] button", clickText: "Revisor de plataforma", capture: true },
  { key: "demo-campos-maintenance", path: "/demo?tab=campos&perspective=admin", userMode: "demo-maintenance", clickSelector: "[data-demo-field-operations='v3.4'] button", clickTextPrefix: "Camp Municipal Demo", capture: true },
  { key: "demo-player-modal", path: "/demo?tab=inicio&perspective=player", userMode: "demo-player", clickSelector: "button", clickText: "Abrir mi ficha", expectedSelector: "[role='dialog']", capture: false },
  { key: "demo-partido", path: "/demo?tab=partido&perspective=admin", userMode: "demo-admin", capture: true },
  { key: "demo-partido-alineacion", path: "/demo?tab=partido&perspective=admin", userMode: "demo-admin", setupClickSelector: "[data-match-state='upcoming'] button", setupExpectedSelector: "aside[aria-label='Secciones del partido']", clickSelector: "aside[aria-label='Secciones del partido'] button", clickText: "Equipos", capture: true },
  { key: "demo-partido-resultado", path: "/demo?tab=partido&perspective=admin", userMode: "demo-admin", setupClickSelector: "[data-match-state='upcoming'] button", setupExpectedSelector: "aside[aria-label='Secciones del partido']", clickSelector: "aside[aria-label='Secciones del partido'] button", clickText: "Resultado", capture: true },
  { key: "demo-partido-admin", path: "/demo?tab=partido&perspective=admin", userMode: "demo-admin", setupClickSelector: "[data-match-state='upcoming'] button", setupExpectedSelector: "aside[aria-label='Secciones del partido']", clickSelector: "aside[aria-label='Secciones del partido'] button", clickText: "Administrar partido", expectedSelector: "[data-match-pane='admin']", capture: true },
  { key: "demo-retos", path: "/demo?tab=retos&perspective=admin", userMode: "demo-admin", capture: true },
  { key: "demo-mercado", path: "/demo?tab=mercado&perspective=admin", userMode: "demo-admin", capture: true },
  { key: "demo-mercado-partidos", path: "/demo?tab=mercado&perspective=admin", userMode: "demo-admin", clickSelector: "aside[aria-label='Secciones de Mercado'] button", clickText: "Partidos", capture: false },
  { key: "demo-mercado-retos", path: "/demo?tab=mercado&perspective=admin", userMode: "demo-admin", clickSelector: "aside[aria-label='Secciones de Mercado'] button", clickText: "Retos", capture: false },
  { key: "demo-mercado-equipos", path: "/demo?tab=mercado&perspective=free-agent", userMode: "demo-free-agent", clickSelector: "aside[aria-label='Secciones de Mercado'] button", clickText: "Equipos", capture: false },
  { key: "mercado-partidos", path: "/mercado", userMode: "visitor", clickSelector: "[data-official-market-navigation='single'] button", clickText: "Partidos", capture: false },
  { key: "mercado-retos", path: "/mercado", userMode: "visitor", clickSelector: "[data-official-market-navigation='single'] button", clickText: "Retos", capture: false },
  { key: "demo-equipo", path: "/demo?tab=equipo&perspective=admin", userMode: "demo-admin", capture: true },
  { key: "demo-equipo-plantilla", path: "/demo?tab=equipo&perspective=admin", userMode: "demo-admin", clickSelector: "aside[aria-label='Secciones de Equipo'] button", clickText: "Plantilla", capture: false },
  { key: "demo-equipo-logros", path: "/demo?tab=equipo&perspective=admin", userMode: "demo-admin", clickSelector: "aside[aria-label='Secciones de Equipo'] button", clickText: "Logros", capture: false },
  { key: "demo-equipo-escudo", path: "/demo?tab=equipo&perspective=admin", userMode: "demo-admin", clickSelector: "aside[aria-label='Secciones de Equipo'] button", clickText: "Escudo", capture: false },
  { key: "demo-perfil", path: "/demo?tab=perfil&perspective=player", userMode: "demo-player", capture: true },
  { key: "demo-perfil-recompensas", path: "/demo?tab=perfil&perspective=player", userMode: "demo-player", clickSelector: "aside[aria-label='Secciones de Perfil'] button", clickText: "Recompensas", capture: false },
  { key: "demo-perfil-avisos", path: "/demo?tab=perfil&perspective=player", userMode: "demo-player", clickSelector: "aside[aria-label='Secciones de Perfil'] button", clickTextPrefix: "Avisos", capture: false },
  { key: "demo-avisos", path: "/demo?tab=avisos&perspective=player", userMode: "demo-player", capture: true },
  { key: "mercado", path: "/mercado", userMode: "visitor", capture: true },
  { key: "retos", path: "/retos", userMode: "visitor", capture: true },
  { key: "perfil", path: "/perfil", userMode: "visitor", capture: true },
  { key: "equipo", path: "/equipo", userMode: "visitor-no-team", capture: true },
  { key: "equipo-plantilla", path: "/equipo/plantilla", userMode: "visitor-no-team", capture: false },
  { key: "equipo-invitaciones", path: "/equipo/invitaciones", userMode: "visitor-no-team", capture: false },
  { key: "campos", path: "/campos", userMode: "visitor", capture: true },
  { key: "reservas", path: "/reservas", userMode: "visitor", capture: true },
  { key: "club-campos", path: "/clubes/gestionar/campos", userMode: "visitor", capture: false },
  { key: "club-reservas", path: "/clubes/gestionar/reservas", userMode: "visitor", capture: false },
  { key: "admin-venues", path: "/admin/venues", userMode: "visitor", capture: false },
  { key: "personalizar-carta", path: "/personalizar-carta", userMode: "visitor", capture: true },
  { key: "equipo-identidad", path: "/equipo/identidad", userMode: "visitor-no-team", capture: true },
  { key: "avisos", path: "/avisos", userMode: "visitor", capture: true },
  { key: "ajustes-notificaciones", path: "/ajustes/notificaciones", userMode: "visitor", capture: true },
  { key: "ranking", path: "/ranking", userMode: "visitor", capture: true },
  { key: "referee-profile", path: "/perfil/arbitro", userMode: "visitor", capture: false },
  { key: "conducta", path: "/perfil/conducta", userMode: "visitor", capture: false },
  { key: "partido-invitado", path: "/partido-invitado", userMode: "visitor", capture: false },
  { key: "invitacion-partido", path: "/invitacion-partido", userMode: "visitor", capture: false },
  { key: "valorar-equipo", path: "/valorar-equipo", userMode: "visitor", capture: false },
  { key: "lab-escudos", path: "/laboratorio-cosmeticos-escudo", userMode: "lab", capture: true },
  { key: "lab-cartas", path: "/laboratorio-cosmeticos-ficha", userMode: "lab", capture: false },
  { key: "lab-rating", path: "/laboratorio-ficha-jugador", userMode: "lab", capture: false },
  { key: "lab-ranking", path: "/laboratorio-ranking-provincial", userMode: "lab", capture: false },
  { key: "lab-premium-art", path: "/laboratorio-premium-art-pack", userMode: "lab", capture: true },
  { key: "lab-league-index", path: "/laboratorio-league-participation", userMode: "lab-r4a", capture: false },
  { key: "lab-league-public", path: "/laboratorio-league-participation?surface=public", userMode: "lab-r4a", capture: true },
  { key: "lab-league-mine", path: "/laboratorio-league-participation?surface=mine", userMode: "lab-r4a", capture: false },
  { key: "lab-league-desk", path: "/laboratorio-league-participation?surface=desk", userMode: "lab-r4a", capture: true },
  { key: "lab-league-entry", path: "/laboratorio-league-participation?surface=entry", userMode: "lab-r4a", capture: false },
  { key: "lab-league-roster", path: "/laboratorio-league-participation?surface=roster", userMode: "lab-r4a", capture: true },
  { key: "lab-league-r4d", path: "/laboratorio-league-operational-exceptions", userMode: "lab-r4d", capture: true },
  { key: "demo-inicio-light", path: "/demo?tab=inicio&perspective=admin&qaTheme=light", userMode: "demo-admin-light", capture: false },
  { key: "demo-inicio-dark", path: "/demo?tab=inicio&perspective=admin&qaTheme=dark", userMode: "demo-admin-dark", capture: false },
  { key: "v21-home", path: "/laboratorio-official-ui-v2-1?surface=inicio&role=admin&state=upcoming&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-home-player", path: "/laboratorio-official-ui-v2-1?surface=inicio&role=player&state=upcoming&capture=1", userMode: "lab-player", capture: false },
  { key: "v21-home-no-team", path: "/laboratorio-official-ui-v2-1?surface=inicio&role=player&state=no-team&capture=1", userMode: "lab-no-team", capture: false },
  { key: "v21-home-offline", path: "/laboratorio-official-ui-v2-1?surface=inicio&role=player&state=offline&capture=1", userMode: "lab-offline", capture: false },
  { key: "v21-match-next", path: "/laboratorio-official-ui-v2-1?surface=partido&pane=proximo&role=admin&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-match-lineup", path: "/laboratorio-official-ui-v2-1?surface=partido&pane=alineacion&role=admin&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-match-result", path: "/laboratorio-official-ui-v2-1?surface=partido&pane=resultado&role=admin&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-match-admin", path: "/laboratorio-official-ui-v2-1?surface=partido&pane=admin&role=admin&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-market", path: "/laboratorio-official-ui-v2-1?surface=mercado&role=admin&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-ranking", path: "/laboratorio-official-ui-v2-1?surface=ranking&capture=1", userMode: "lab-player", capture: true },
  { key: "v21-notifications", path: "/laboratorio-official-ui-v2-1?surface=avisos&capture=1", userMode: "lab-player", capture: true },
  { key: "v21-card", path: "/laboratorio-official-ui-v2-1?surface=carta&capture=1", userMode: "lab-player", capture: true },
  { key: "v21-shield", path: "/laboratorio-official-ui-v2-1?surface=escudo&capture=1", userMode: "lab-admin", capture: true },
  { key: "v21-team", path: "/laboratorio-official-ui-v2-1?surface=equipo&capture=1", userMode: "lab-player", capture: false },
  { key: "v21-referee", path: "/laboratorio-official-ui-v2-1?surface=arbitro&capture=1", userMode: "lab-referee", capture: false },
  { key: "v21-home-light", path: "/laboratorio-official-ui-v2-1?surface=inicio&theme=light&capture=1", userMode: "lab-light", capture: false },
];

const viewportFilter = requestedKeys("VISUAL_AUDIT_VIEWPORTS");
const surfaceFilter = requestedKeys("VISUAL_AUDIT_SURFACES");
const selectedViewports = viewportFilter.size ? viewports.filter(({ key }) => viewportFilter.has(key)) : viewports;
const selectedSurfaces = surfaceFilter.size ? surfaces.filter(({ key }) => surfaceFilter.has(key)) : surfaces;

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

async function openPage(port, preferExistingPage = false) {
  if (preferExistingPage) {
    for (let attempt = 0; attempt < 60; attempt += 1) {
      const targets = await fetch(`http://127.0.0.1:${port}/json/list`)
        .then((response) => response.json())
        .catch(() => []);
      const target = targets.find((item) => item.type === "page" && item.webSocketDebuggerUrl);
      if (target) return connectSocket(target.webSocketDebuggerUrl);
      await delay(100);
    }
    throw new Error("Chrome app-mode page target was not created.");
  }
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

async function waitForPageCondition(client, expression, attempts = 100) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (await evaluate(client, expression)) return;
    await delay(100);
  }
  throw new Error(`Page condition did not become true: ${expression}`);
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
    const interactiveRect = (element) => {
      const rect = element.getBoundingClientRect();
      if (element instanceof HTMLInputElement && (element.type === "checkbox" || element.type === "radio")) {
        const explicitLabel = element.id ? document.querySelector('label[for="' + CSS.escape(element.id) + '"]') : null;
        const label = element.closest("label") || explicitLabel;
        if (label && visible(label)) return label.getBoundingClientRect();
      }
      return rect;
    };
    const controls = [...document.querySelectorAll("button, a[href], input, select, textarea, [role='button'], [role='tab']")]
      .filter(visible)
      .map((element) => ({ element, rect: interactiveRect(element) }));
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
    const gameChromeViolations = [...document.querySelectorAll(
      ".mobile-app-nav a, .mobile-app-nav button, .match-manager-subnav button, .lineup-side-tools button"
    )]
      .filter(visible)
      .map((element) => ({ element, rect: interactiveRect(element) }))
      .filter(({ rect }) => rect.left < -2 || rect.right > viewport.width + 2 || rect.top < -2 || rect.bottom > viewport.height + 2)
      .slice(0, 20)
      .map(({ element, rect }) => ({
        ...descriptor(element),
        left: Math.round(rect.left), right: Math.round(rect.right), top: Math.round(rect.top), bottom: Math.round(rect.bottom),
      }));
    const failedImages = [...document.images]
      .filter((image) => image.complete && image.naturalWidth === 0)
      .map((image) => image.currentSrc || image.src || image.alt || "unknown");
    const demoShell = document.querySelector("main[data-demo-world]");
    const demoPalette = demoShell ? {
      backgroundColor: getComputedStyle(demoShell).backgroundColor,
      color: getComputedStyle(demoShell).color,
    } : null;
    const navigation = performance.getEntriesByType("navigation")[0];
    const firstContentfulPaint = performance.getEntriesByName("first-contentful-paint")[0];
    const rectOf = (selector) => {
      const element = document.querySelector(selector);
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      return {
        bottom: Math.round(rect.bottom),
        display: getComputedStyle(element).display,
        height: Math.round(rect.height),
        left: Math.round(rect.left),
        right: Math.round(rect.right),
        top: Math.round(rect.top),
        width: Math.round(rect.width),
      };
    };
    return {
      title: document.title,
      theme: doc.dataset.theme || getComputedStyle(doc).colorScheme || "",
      displayMode: matchMedia("(display-mode: standalone)").matches
        ? "standalone"
        : matchMedia("(display-mode: fullscreen)").matches ? "fullscreen" : "browser",
      manifestHref: document.querySelector('link[rel="manifest"]')?.getAttribute("href") || null,
      serviceWorkerControlled: Boolean(navigator.serviceWorker?.controller),
      textLength: (body.innerText || "").trim().length,
      overflowX: Math.max(doc.scrollWidth, body.scrollWidth) - Math.max(doc.clientWidth, window.innerWidth),
      overflowY: Math.max(doc.scrollHeight, body.scrollHeight) - Math.max(doc.clientHeight, window.innerHeight),
      failedImages,
      demoPalette,
      performance: {
        cls: Number((globalThis.__pachangasVisualAuditCls || 0).toFixed(4)),
        domContentLoadedMs: Math.round(navigation?.domContentLoadedEventEnd || 0),
        firstContentfulPaintMs: Math.round(firstContentfulPaint?.startTime || 0),
        loadMs: Math.round(navigation?.loadEventEnd || 0),
        resourceCount: performance.getEntriesByType("resource").length,
        transferBytes: Math.round(performance.getEntriesByType("resource").reduce((total, entry) => total + (entry.transferSize || 0), 0)),
      },
      smallTargets,
      viewportViolations,
      gameChromeViolations,
      gameLayout: {
        activeContext: rectOf(".match-active-context"),
        appShell: rectOf(".app-shell"),
        main: rectOf("main[data-mobile-tab]"),
        mainScrollTop: document.querySelector("main[data-mobile-tab]")?.scrollTop ?? null,
        mobileNav: rectOf(".mobile-app-nav"),
        scrollY: Math.round(window.scrollY),
      },
      activeElement: descriptor(document.activeElement || body),
    };
  })()`;
}

function resetScrollExpression() {
  return `(() => {
    document.documentElement.style.scrollBehavior = "auto";
    document.body.style.scrollBehavior = "auto";
    window.scrollTo(0, 0);
    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;
    for (const element of document.querySelectorAll("*")) {
      if (element.scrollTop > 0) element.scrollTop = 0;
      if (element.scrollLeft > 0) element.scrollLeft = 0;
    }
  })()`;
}

function markdownReport(results) {
  const rows = results.map((result) => {
    const status = result.navigationError || result.consoleErrors.length || result.failedRequests.length
      || result.metrics.failedImages.length || result.metrics.overflowX > 2 || result.metrics.viewportViolations.length
      || result.metrics.gameChromeViolations.length
      || (result.viewportKey === "pwa-portrait" && result.metrics.displayMode !== "standalone")
      || (result.viewportKey === "pwa-portrait" && !result.metrics.serviceWorkerControlled)
      ? "REVIEW"
      : "PASS";
    return `| ${result.surface} | ${result.userMode} | ${result.viewport} | ${status} | ${result.metrics.overflowX} | ${result.consoleErrors.length} | ${result.consoleWarnings.length} | ${result.metrics.failedImages.length} | ${result.metrics.smallTargets.length} | ${result.metrics.gameChromeViolations.length} |`;
  });
  return [
    `# Visual Audit ${label}`,
    "",
    `Base URL: \`${baseUrl}\``,
    "",
    "| Route | User mode | Viewport | Result | Overflow X | Console errors | Warnings | Broken images | Small targets | Game chrome |",
    "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
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
    appMode ? `--app=${baseUrl}` : "about:blank",
  ], { stdio: "ignore" });

  try {
    await waitForJson(`http://127.0.0.1:${port}/json/version`);
    const client = await openPage(port, appMode);
    await Promise.all([
      client.send("Page.enable"),
      client.send("Runtime.enable"),
      client.send("Network.enable"),
    ]);
    await client.send("Network.setCacheDisabled", { cacheDisabled: true });
    await client.send("Page.addScriptToEvaluateOnNewDocument", {
      source: `
        globalThis.__pachangasVisualAuditCls = 0;
        try {
          new PerformanceObserver((list) => {
            for (const entry of list.getEntries()) {
              if (!entry.hadRecentInput) globalThis.__pachangasVisualAuditCls += entry.value;
            }
          }).observe({ type: "layout-shift", buffered: true });
        } catch {}
        try {
          if (new URL(location.href).searchParams.has("qaPlayer")) sessionStorage.setItem("pachangas-admin-view-preview", "player");
          else sessionStorage.removeItem("pachangas-admin-view-preview");
        } catch {}
      `,
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
    for (const viewport of selectedViewports) {
      await client.send("Emulation.setEmulatedMedia", {
        features: [
          ...(viewport.displayMode ? [{ name: "display-mode", value: viewport.displayMode }] : []),
          ...(viewport.reducedMotion ? [{ name: "prefers-reduced-motion", value: "reduce" }] : []),
          ...(viewport.colorScheme ? [{ name: "prefers-color-scheme", value: viewport.colorScheme }] : []),
        ],
      });
      await client.send("Emulation.setDeviceMetricsOverride", {
        deviceScaleFactor: 1,
        height: viewport.height,
        mobile: viewport.width < 900,
        width: viewport.width,
      });
      for (const surface of selectedSurfaces) {
        if (viewport.surfaceKeys && !viewport.surfaceKeys.includes(surface.key)) continue;
        consoleErrors = [];
        consoleWarnings = [];
        failedRequests = [];
        let navigationError = "";
        try {
          const url = new URL(surface.path, baseUrl).toString();
          await client.send("Page.navigate", { url });
          await delay(650);
          await evaluate(client, "document.fonts?.ready ?? Promise.resolve()");
          if (viewport.displayMode) {
            const workerReady = await evaluate(client, `(async () => {
              if (!("serviceWorker" in navigator)) return false;
              return Promise.race([
                navigator.serviceWorker.ready.then(() => true),
                new Promise((resolve) => setTimeout(() => resolve(false), 2_000)),
              ]);
            })()`);
            if (workerReady && !(await evaluate(client, "Boolean(navigator.serviceWorker.controller)"))) {
              await client.send("Page.reload", { ignoreCache: true });
              await delay(650);
              await evaluate(client, "document.fonts?.ready ?? Promise.resolve()");
            }
          }
          if (new URL(surface.path, baseUrl).pathname === "/demo") {
            await waitForPageCondition(client, `Boolean(document.querySelector("[data-demo-world='ready']"))`);
          }
          const qaTheme = viewport.colorScheme ?? new URL(surface.path, baseUrl).searchParams.get("qaTheme");
          if (qaTheme === "light" || qaTheme === "dark") {
            await evaluate(client, `(() => {
              for (const element of [document.documentElement, document.body]) {
                element.dataset.theme = ${JSON.stringify(qaTheme)};
                element.style.colorScheme = ${JSON.stringify(qaTheme)};
              }
            })()`);
          }
          const actions = [
            ...(surface.setupClickSelector ? [{
              expectedSelector: surface.setupExpectedSelector,
              selector: surface.setupClickSelector,
              text: surface.setupClickText ?? null,
            }] : []),
            ...((surface.clickText ?? surface.clickTextPrefix) ? [{
              expectedSelector: surface.expectedSelector,
              prefix: Boolean(surface.clickTextPrefix),
              selector: surface.clickSelector ?? "button, a[href], [role='tab']",
              text: surface.clickText ?? surface.clickTextPrefix,
            }] : []),
          ];
          for (const action of actions) {
            const clicked = await evaluate(client, `(() => {
              const expected = ${JSON.stringify(action.text)};
              const prefix = ${JSON.stringify(Boolean(action.prefix))};
              const target = [...document.querySelectorAll(${JSON.stringify(action.selector)})]
                .find((element) => {
                  if (expected === null) return true;
                  const text = (element.textContent || "").trim();
                  return prefix ? text.startsWith(expected) : text === expected;
                });
              if (!target) return false;
              target.click();
              return true;
            })()`);
            if (!clicked) throw new Error(`Post-navigation action not found: ${action.text ?? action.selector}`);
            await delay(300);
            const actionConfirmed = action.expectedSelector
              ? await evaluate(client, `Boolean(document.querySelector(${JSON.stringify(action.expectedSelector)}))`)
              : await evaluate(client, `(() => {
                const expected = ${JSON.stringify(action.text)};
                const prefix = ${JSON.stringify(Boolean(action.prefix))};
                const target = [...document.querySelectorAll(${JSON.stringify(action.selector)})]
                  .find((element) => {
                    const text = (element.textContent || "").trim();
                    return prefix ? text.startsWith(expected) : text === expected;
                  });
                return Boolean(target && (target.matches(".active, .selected") || target.getAttribute("aria-current") === "page"));
              })()`);
            if (!actionConfirmed) throw new Error(`Post-navigation action did not become active: ${action.text ?? action.selector}`);
          }
          await evaluate(client, resetScrollExpression());
          await evaluate(client, "new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)))");
          await evaluate(client, resetScrollExpression());
          await delay(50);
        } catch (error) {
          navigationError = error instanceof Error ? error.message : String(error);
        }
        const metrics = await evaluate(client, auditExpression());
        const result = {
          surface: surface.key,
          path: surface.path,
          userMode: surface.userMode,
          viewportKey: viewport.key,
          viewport: `${viewport.width}x${viewport.height}`,
          metrics,
          consoleErrors: [...new Set(consoleErrors)],
          consoleWarnings: [...new Set(consoleWarnings)],
          failedRequests: [...new Set(failedRequests)],
          navigationError,
        };
        results.push(result);

        if (captureScreenshots && surface.capture && viewport.capture) {
          await evaluate(client, resetScrollExpression());
          await evaluate(client, "new Promise((resolve) => requestAnimationFrame(resolve))");
          const screenshot = await client.send("Page.captureScreenshot", {
            captureBeyondViewport: false,
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

    if (captureScreenshots) {
      await client.send("Emulation.setEmulatedMedia", { features: [] });
      await client.send("Emulation.setDeviceMetricsOverride", {
        deviceScaleFactor: 1,
        height: 900,
        mobile: false,
        width: 1440,
      });
      await client.send("Page.navigate", { url: new URL("/laboratorio-premium-art-pack", baseUrl).toString() });
      await delay(900);
      await evaluate(client, "document.fonts?.ready ?? Promise.resolve()");
      const layout = await client.send("Page.getLayoutMetrics");
      const contentSize = layout.cssContentSize ?? layout.contentSize;
      const contactSheet = await client.send("Page.captureScreenshot", {
        captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: Math.min(1440, contentSize.width), height: contentSize.height, scale: 1 },
        format: "jpeg",
        fromSurface: true,
        quality: 88,
      });
      await writeFile(
        path.join(outputRoot, "premium-art-pack-contact-sheet.jpg"),
        Buffer.from(contactSheet.data, "base64"),
      );
    }

    await writeFile(path.join(outputRoot, "results.json"), `${JSON.stringify(results, null, 2)}\n`);
    await writeFile(path.join(outputRoot, "matrix.md"), markdownReport(results));
    client.close();
    console.log(JSON.stringify({ outputRoot, results: results.length }, null, 2));
  } finally {
    browser.kill();
    if (browser.exitCode === null) {
      await Promise.race([once(browser, "exit"), delay(2_000)]);
    }
    await rm(userDataDir, { force: true, maxRetries: 8, recursive: true, retryDelay: 120 });
  }
}

await main();
