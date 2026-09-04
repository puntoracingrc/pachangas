import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir, platform } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

import { createClient } from "@supabase/supabase-js";

const PRODUCTION_REF = "qonbngfrnrqgmxbdfbea";
const REQUIRED_CONFIRMATION = "GOOGLE_PLACES_ISSUE_166_STAGING_ONLY";
const SELECT_ALL_MODIFIER = platform() === "darwin" ? 4 : 2;
const env = {
  bypassSecret: process.env.GOOGLE_PLACES_PREVIEW_BYPASS_SECRET,
  confirmation: process.env.GOOGLE_PLACES_PREVIEW_CONFIRM,
  expectedKeyFingerprint: process.env.GOOGLE_PLACES_PREVIEW_EXPECTED_KEY_FINGERPRINT,
  expectedSha: process.env.GOOGLE_PLACES_PREVIEW_EXPECTED_SHA,
  previewUrl: process.env.GOOGLE_PLACES_PREVIEW_URL,
  productionKeyFingerprint: process.env.GOOGLE_PLACES_PRODUCTION_KEY_FINGERPRINT,
  projectRef: process.env.GOOGLE_PLACES_PREVIEW_PROJECT_REF,
  query: process.env.GOOGLE_PLACES_PREVIEW_QUERY ?? "Ciudad Deportiva Dani Jarque",
  shareUrl: process.env.GOOGLE_PLACES_PREVIEW_SHARE_URL,
};

const previewTarget = env.previewUrl ? new URL(env.previewUrl) : null;
const shareTarget = env.shareUrl ? new URL(env.shareUrl) : null;
const fingerprintPattern = /^[0-9a-f]{64}$/i;

if (
  env.confirmation !== REQUIRED_CONFIRMATION
  || !env.projectRef
  || env.projectRef === PRODUCTION_REF
  || !/^[0-9a-f]{40}$/i.test(env.expectedSha ?? "")
  || !fingerprintPattern.test(env.expectedKeyFingerprint ?? "")
  || !fingerprintPattern.test(env.productionKeyFingerprint ?? "")
  || env.expectedKeyFingerprint === env.productionKeyFingerprint
  || !previewTarget
  || /(^|\.)pachangasiq\.com$/i.test(previewTarget.hostname)
  || (!env.bypassSecret && !shareTarget)
  || (shareTarget && (
    shareTarget.hostname !== previewTarget.hostname
    || !shareTarget.searchParams.has("_vercel_share")
  ))
) {
  throw new Error("GOOGLE_PLACES_ISSUE_166_PRODUCTION_TARGET_FORBIDDEN");
}

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

function loadEphemeralApiKeys() {
  const result = spawnSync(
    "supabase",
    ["projects", "api-keys", "--project-ref", env.projectRef, "--output", "json"],
    { encoding: "utf8", maxBuffer: 4 * 1024 * 1024 },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error("GOOGLE_PLACES_STAGING_API_KEYS_UNAVAILABLE");

  const keys = JSON.parse(result.stdout);
  const publishable = keys.find((entry) => entry.type === "publishable")
    ?? keys.find((entry) => entry.name === "anon");
  const serviceRole = keys.find((entry) => entry.name === "service_role");
  if (!publishable?.api_key || !serviceRole?.api_key) {
    throw new Error("GOOGLE_PLACES_STAGING_KEYS_INCOMPLETE");
  }
  if (/^sb_secret_/i.test(publishable.api_key) || publishable.api_key === serviceRole.api_key) {
    throw new Error("GOOGLE_PLACES_STAGING_BROWSER_KEY_INVALID");
  }
  return { publishableKey: publishable.api_key, serviceRoleKey: serviceRole.api_key };
}

function supabaseClient(url, key) {
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 10 } },
  });
}

function metadata(surface) {
  return {
    clientVersion: `4.0.0+places166.${env.expectedSha.slice(0, 12)}`,
    displayMode: "browser",
    serviceWorkerVersion: `4.0.0+sw.${env.expectedSha.slice(0, 12)}`,
    surface,
  };
}

async function rpcOk(client, name, args) {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(`${name}:${result.error.code ?? "ERROR"}:${result.error.message}`);
  return result.data;
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

async function waitForJson(url, attempts = 80) {
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) return response.json();
      lastError = new Error(`${response.status} ${response.statusText}`);
    } catch (error) {
      lastError = error;
    }
    await delay(125);
  }
  throw lastError ?? new Error(`No response from ${url}`);
}

async function openPage(port) {
  const target = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })
    .then((response) => response.json());
  return connectSocket(target.webSocketDebuggerUrl);
}

async function openExistingPage(port) {
  const targets = await waitForJson(`http://127.0.0.1:${port}/json/list`);
  const target = targets.find((entry) => entry.type === "page" && entry.webSocketDebuggerUrl);
  if (!target) throw new Error("GOOGLE_PLACES_PWA_PAGE_TARGET_MISSING");
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

async function waitForCondition(client, expression, label, attempts = 180) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (await evaluate(client, expression)) return;
    await delay(125);
  }
  throw new Error(`GOOGLE_PLACES_PREVIEW_TIMEOUT:${label}`);
}

async function teamBootstrapDiagnostic(client, authStorageKey) {
  return evaluate(client, `(() => {
    let auth = null;
    try {
      const stored = JSON.parse(localStorage.getItem(${JSON.stringify(authStorageKey)}) || "null");
      auth = {
        hasAccessToken: Boolean(stored?.access_token),
        hasRefreshToken: Boolean(stored?.refresh_token),
        hasUser: Boolean(stored?.user?.id),
        unexpired: Number(stored?.expires_at || 0) * 1000 > Date.now(),
      };
    } catch {
      auth = { malformed: true };
    }
    const bodyText = String(document.body?.innerText || "");
    const main = document.querySelector("main[data-team-state]");
    return {
      auth,
      hasMain: Boolean(main),
      hasSignIn: /Entrar con Google/i.test(bodyText),
      hasTeamAccessDenied: /No tienes acceso a este grupo/i.test(bodyText),
      hasVercelProtection: /Vercel Authentication/i.test(bodyText),
      host: location.hostname,
      bodyChildren: [...(document.body?.children || [])].slice(0, 8).map((element) => ({
        className: String(element.className || "").slice(0, 80),
        tag: element.tagName,
      })),
      bodyHtmlLength: document.body?.innerHTML.length || 0,
      bodyTextLength: bodyText.length,
      path: location.pathname,
      resourceCount: performance.getEntriesByType("resource").length,
      scriptCount: document.scripts.length,
      teamState: main?.getAttribute("data-team-state") || "missing",
      title: document.title,
    };
  })()`);
}

function waitForProtocolEvent(client, method, timeoutMs = 30000) {
  let dispose = () => {};
  let timer;
  const event = new Promise((resolve, reject) => {
    dispose = client.onEvent((message) => {
      if (message.method !== method) return;
      clearTimeout(timer);
      resolve(message.params);
    });
    timer = setTimeout(() => reject(new Error(`GOOGLE_PLACES_PREVIEW_PROTOCOL_TIMEOUT:${method}`)), timeoutMs);
  });
  return event.finally(() => {
    clearTimeout(timer);
    dispose();
  });
}

async function navigate(client, url) {
  const loaded = waitForProtocolEvent(client, "Page.loadEventFired");
  const navigation = await client.send("Page.navigate", { url });
  if (navigation.errorText) throw new Error(`GOOGLE_PLACES_PREVIEW_NAVIGATION_FAILED:${navigation.errorText}`);
  await loaded;
  await waitForCondition(client, "document.readyState === 'complete'", "document-ready");
}

async function installPreviewBypass(client, onUnexpectedProtocolError) {
  if (!env.bypassSecret) return;
  await client.send("Fetch.enable", {
    patterns: [{ requestStage: "Request", urlPattern: `${previewTarget.origin}/*` }],
  });
  client.onEvent((message) => {
    if (message.method !== "Fetch.requestPaused") return;
    const requestUrl = new URL(message.params.request.url);
    const headers = Object.entries(message.params.request.headers ?? {})
      .filter(([name]) => name.toLowerCase() !== "x-vercel-protection-bypass")
      .map(([name, value]) => ({ name, value: String(value) }));
    if (requestUrl.hostname === previewTarget.hostname) {
      headers.push({ name: "x-vercel-protection-bypass", value: env.bypassSecret });
      headers.push({ name: "x-vercel-set-bypass-cookie", value: "true" });
    }
    void client.send("Fetch.continueRequest", { headers, requestId: message.params.requestId }).catch((error) => {
      // Chrome can retire a paused request while a navigation or target is closing.
      if (/^Invalid InterceptionId\.?$/.test(error instanceof Error ? error.message : String(error))) return;
      onUnexpectedProtocolError(error);
    });
  });
}

function visibilitySource() {
  return `(element) => {
    if (!element) return false;
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0
      && rect.width > 0 && rect.height > 0;
  }`;
}

async function clickByText(client, text, selector = "button, a[href], [role='button'], [role='tab']", exact = true) {
  const clicked = await evaluate(client, `(() => {
    const visible = ${visibilitySource()};
    const target = ${JSON.stringify(text)};
    const normalize = (value) => String(value || "").trim().replace(/\\s+/g, " ");
    const element = [...document.querySelectorAll(${JSON.stringify(selector)})]
      .filter(visible)
      .find((entry) => ${exact ? "normalize(entry.textContent) === target" : "normalize(entry.textContent).includes(target)"});
    if (!element || element.hasAttribute("disabled")) return false;
    element.scrollIntoView({ block: "center", inline: "center" });
    element.click();
    return true;
  })()`);
  assert.equal(clicked, true, `Visible enabled control not found: ${text}`);
}

async function elementState(client, selector) {
  return evaluate(client, `(() => {
    const element = document.querySelector(${JSON.stringify(selector)});
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return {
      disabled: element.hasAttribute("disabled"),
      height: rect.height,
      text: String(element.textContent || "").trim().replace(/\\s+/g, " "),
      width: rect.width,
    };
  })()`);
}

async function setViewport(client, { displayMode = "browser", height, mobile, width }) {
  touchInputEnabled = mobile;
  await client.send("Emulation.setEmulatedMedia", {
    features: [{ name: "display-mode", value: displayMode }],
  });
  await client.send("Emulation.setDeviceMetricsOverride", {
    deviceScaleFactor: mobile ? 2 : 1,
    height,
    mobile,
    screenHeight: height,
    screenWidth: width,
    width,
  });
  await client.send("Emulation.setTouchEmulationEnabled", {
    enabled: mobile,
    maxTouchPoints: mobile ? 5 : 1,
  });
  await delay(300);
}

async function observePlacesEvents(client) {
  await evaluate(client, `(() => {
    const widget = document.querySelector("gmp-place-autocomplete");
    if (!widget) return false;
    globalThis.__places166 = { error: 0, select: 0 };
    widget.addEventListener("gmp-error", () => { globalThis.__places166.error += 1; });
    widget.addEventListener("gmp-select", () => { globalThis.__places166.select += 1; });
    return true;
  })()`);
}

async function openVenueFormAtViewport(client, viewport, teamUrl) {
  await setViewport(client, viewport);
  await navigate(client, teamUrl);
  await client.send("Emulation.setEmulatedMedia", {
    features: [{ name: "display-mode", value: viewport.displayMode ?? "browser" }],
  });
  await waitForCondition(client, `Boolean(document.querySelector("main[data-team-state='member']"))`, `${viewport.label}-team-member`);
  await waitForCondition(client, `Boolean(document.querySelector("[data-view='overview']"))`, `${viewport.label}-overview`);
  const hasDraft = await evaluate(client, `Boolean(document.querySelector("[aria-label='Borradores de partido'] button"))`);
  if (hasDraft) {
    await clickByText(client, "Continuar", "[aria-label='Borradores de partido'] button");
  } else {
    await clickByText(client, "Crear partido", "[data-view='overview'] button");
  }
  await waitForCondition(client, `Boolean(document.querySelector("[data-view='wizard']"))`, `${viewport.label}-wizard`);
  await clickByText(client, "Añadir campo", "[data-view='wizard'] button");
  await waitForCondition(client, `Boolean(document.querySelector(".top-venue-form gmp-place-autocomplete"))`, `${viewport.label}-places-widget`);
  await observePlacesEvents(client);
}

async function focusWidget(client) {
  await evaluate(client, `document.querySelector("gmp-place-autocomplete")?.scrollIntoView({ behavior: "instant", block: "center", inline: "center" })`);
  await delay(200);
  const bounds = await evaluate(client, `(() => {
    const element = document.querySelector("gmp-place-autocomplete");
    if (!element) return null;
    element.focus({ preventScroll: true });
    const rect = element.getBoundingClientRect();
    return {
      bottom: rect.bottom,
      left: rect.left,
      right: rect.right,
      top: rect.top,
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2,
    };
  })()`);
  assert.ok(bounds, "Google Places widget is missing");
  if (touchInputEnabled) {
    const tree = await client.send("Accessibility.getFullAXTree");
    let accessibleInput = null;
    for (const node of tree.nodes ?? []) {
      if (!["combobox", "textbox"].includes(node.role?.value) || !node.backendDOMNodeId) continue;
      try {
        const model = await client.send("DOM.getBoxModel", { backendNodeId: node.backendDOMNodeId });
        const quad = model.model?.border;
        if (!Array.isArray(quad) || quad.length !== 8) continue;
        const x = (quad[0] + quad[2] + quad[4] + quad[6]) / 4;
        const y = (quad[1] + quad[3] + quad[5] + quad[7]) / 4;
        if (x >= bounds.left && x <= bounds.right && y >= bounds.top && y <= bounds.bottom) {
          accessibleInput = { backendNodeId: node.backendDOMNodeId, x, y };
          break;
        }
      } catch {
        // A collapsed native select has no pointer surface inside the Places widget.
      }
    }
    if (!accessibleInput) {
      await client.send("Input.dispatchTouchEvent", {
        touchPoints: [{ id: 1, radiusX: 1, radiusY: 1, x: bounds.x, y: bounds.y }],
        type: "touchStart",
      });
      await client.send("Input.dispatchTouchEvent", { touchPoints: [], type: "touchEnd" });
      await client.send("Input.dispatchMouseEvent", {
        button: "left",
        clickCount: 1,
        type: "mousePressed",
        x: bounds.x,
        y: bounds.y,
      });
      await client.send("Input.dispatchMouseEvent", {
        button: "left",
        clickCount: 1,
        type: "mouseReleased",
        x: bounds.x,
        y: bounds.y,
      });
      await delay(100);
      return;
    }
    let accessibleCombobox = accessibleInput;
    if (!accessibleCombobox) {
      const widgetObject = await client.send("Runtime.evaluate", {
        expression: 'document.querySelector("gmp-place-autocomplete")',
        returnByValue: false,
      });
      const widgetDescription = await client.send("DOM.describeNode", { objectId: widgetObject.result.objectId });
      accessibleCombobox = {
        backendDOMNodeId: widgetDescription.node.backendNodeId,
        x: bounds.x,
        y: bounds.y,
      };
      await client.send("Runtime.releaseObject", { objectId: widgetObject.result.objectId });
    }
    const touchPoint = accessibleCombobox;
    await client.send("DOM.focus", { backendNodeId: accessibleCombobox.backendNodeId });
    await client.send("Input.dispatchTouchEvent", {
      touchPoints: [{ id: 1, radiusX: 1, radiusY: 1, x: touchPoint.x, y: touchPoint.y }],
      type: "touchStart",
    });
    await client.send("Input.dispatchTouchEvent", { touchPoints: [], type: "touchEnd" });
    await client.send("DOM.focus", { backendNodeId: accessibleCombobox.backendNodeId });
  } else {
    await client.send("Input.dispatchMouseEvent", { button: "left", clickCount: 1, type: "mousePressed", x: bounds.x, y: bounds.y });
    await client.send("Input.dispatchMouseEvent", { button: "left", clickCount: 1, type: "mouseReleased", x: bounds.x, y: bounds.y });
  }
  await delay(100);
}

async function clearFocusedText(client) {
  const modifiers = SELECT_ALL_MODIFIER === 4 ? [2, 4] : [4, 2];
  for (const modifier of modifiers) {
    await client.send("Input.dispatchKeyEvent", { code: "KeyA", key: "a", modifiers: modifier, type: "rawKeyDown" });
    await client.send("Input.dispatchKeyEvent", { code: "KeyA", key: "a", modifiers: modifier, type: "keyUp" });
  }
  await client.send("Input.dispatchKeyEvent", { code: "Backspace", key: "Backspace", type: "rawKeyDown" });
  await client.send("Input.dispatchKeyEvent", { code: "Backspace", key: "Backspace", type: "keyUp" });
  const tree = await client.send("Accessibility.getFullAXTree");
  const focusedTextbox = (tree.nodes ?? []).find((node) => (
    node.role?.value === "textbox"
    && node.properties?.some((property) => property.name === "focused" && property.value?.value === true)
  ));
  const remainingLength = String(focusedTextbox?.value?.value ?? "").length;
  for (let index = 0; index < Math.min(remainingLength + 2, 128); index += 1) {
    await client.send("Input.dispatchKeyEvent", { autoRepeat: index > 0, code: "Backspace", key: "Backspace", type: "rawKeyDown" });
  }
  if (remainingLength > 0) {
    await client.send("Input.dispatchKeyEvent", { code: "Backspace", key: "Backspace", type: "keyUp" });
  }
  await delay(100);
}

async function typeWidgetQuery(client, query) {
  await focusWidget(client);
  await clearFocusedText(client);
  await client.send("Input.insertText", { text: query });
}

async function predictionOptions(client) {
  const tree = await client.send("Accessibility.getFullAXTree");
  const nodesById = new Map((tree.nodes ?? []).map((node) => [node.nodeId, node]));
  const candidates = (tree.nodes ?? []).filter((node) => (
    node.role?.value === "option"
    && !node.ignored
    && node.backendDOMNodeId
    && nodesById.get(node.parentId)?.role?.value === "listbox"
    && String(node.name?.value ?? "").trim()
  ));
  const visible = [];
  for (const candidate of candidates) {
    try {
      const model = await client.send("DOM.getBoxModel", { backendNodeId: candidate.backendDOMNodeId });
      const quad = model.model?.border;
      if (!Array.isArray(quad) || quad.length !== 8) continue;
      const width = Math.max(quad[0], quad[2], quad[4], quad[6]) - Math.min(quad[0], quad[2], quad[4], quad[6]);
      const height = Math.max(quad[1], quad[3], quad[5], quad[7]) - Math.min(quad[1], quad[3], quad[5], quad[7]);
      if (width > 40 && height > 8) visible.push({ ...candidate, box: { height, width } });
    } catch {
      // Collapsed native select options have no visible pointer target.
    }
  }
  return visible;
}

async function predictionDiagnostic(client) {
  const tree = await client.send("Accessibility.getFullAXTree");
  const accessibleCandidates = [];
  const roleCounts = {};
  const trackedRoles = new Set(["combobox", "listbox", "menu", "menuitem", "option", "textbox"]);
  for (const node of tree.nodes ?? []) {
    const role = String(node.role?.value ?? "");
    if (trackedRoles.has(role)) roleCounts[role] = (roleCounts[role] ?? 0) + 1;
    if (!["combobox", "textbox"].includes(role) || !node.backendDOMNodeId) continue;
    try {
      const model = await client.send("DOM.getBoxModel", { backendNodeId: node.backendDOMNodeId });
      const quad = model.model?.border;
      if (!Array.isArray(quad) || quad.length !== 8) continue;
      accessibleCandidates.push({
        focused: node.properties?.some((property) => property.name === "focused" && property.value?.value === true) ?? false,
        height: Math.round(Math.max(quad[1], quad[3], quad[5], quad[7]) - Math.min(quad[1], quad[3], quad[5], quad[7])),
        name: String(node.name?.value ?? "").slice(0, 80),
        role,
        width: Math.round(Math.max(quad[0], quad[2], quad[4], quad[6]) - Math.min(quad[0], quad[2], quad[4], quad[6])),
        x: Math.round(Math.min(quad[0], quad[2], quad[4], quad[6])),
        y: Math.round(Math.min(quad[1], quad[3], quad[5], quad[7])),
      });
    } catch {
      // Hidden controls do not add useful geometry to the diagnostic.
    }
  }
  const focused = (tree.nodes ?? []).find((node) => (
    node.properties?.some((property) => property.name === "focused" && property.value?.value === true)
  ));
  const dom = await evaluate(client, `(() => {
    const widget = document.querySelector("gmp-place-autocomplete");
    const rect = widget?.getBoundingClientRect();
    const describe = (element) => element ? {
      ariaLabel: element.getAttribute?.("aria-label") || "",
      className: String(element.className || "").slice(0, 80),
      placeholder: element.getAttribute?.("placeholder") || "",
      tag: element.tagName || "",
      type: element.getAttribute?.("type") || "",
    } : null;
    return {
      activeElement: describe(document.activeElement),
      errorEvents: globalThis.__places166?.error ?? 0,
      focusedTag: document.activeElement?.tagName || "",
      hitStack: rect ? document.elementsFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2).slice(0, 5).map(describe) : [],
      online: navigator.onLine,
      widgetHeight: Math.round(rect?.height || 0),
      widgetWidth: Math.round(rect?.width || 0),
    };
  })()`);
  return {
    accessibleCandidates,
    dom,
    focusedRole: String(focused?.role?.value ?? ""),
    focusedValueLength: String(focused?.value?.value ?? "").length,
    googleNetwork: networkEvidence.filter((entry) => /googleapis\.com$/.test(entry.host)).slice(-12),
    roleCounts,
  };
}

async function waitForPredictionOptions(client, label = "query") {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const options = await predictionOptions(client);
    if (options.length > 0) return options;
    await delay(125);
  }
  throw new Error(`GOOGLE_PLACES_REAL_PREDICTIONS_NOT_VISIBLE:${label}:${JSON.stringify(await predictionDiagnostic(client))}`);
}

async function selectPredictionByKeyboard(client) {
  await client.send("Input.dispatchKeyEvent", { code: "ArrowDown", key: "ArrowDown", type: "rawKeyDown" });
  await client.send("Input.dispatchKeyEvent", { code: "ArrowDown", key: "ArrowDown", type: "keyUp" });
  await client.send("Input.dispatchKeyEvent", { code: "Enter", key: "Enter", type: "rawKeyDown" });
  await client.send("Input.dispatchKeyEvent", { code: "Enter", key: "Enter", type: "keyUp" });
}

async function selectPredictionByPointer(client, option) {
  const resolved = await client.send("DOM.resolveNode", { backendNodeId: option.backendDOMNodeId });
  const objectId = resolved.object?.objectId;
  assert.ok(objectId, "Prediction option cannot be resolved for pointer input");
  const rectResult = await client.send("Runtime.callFunctionOn", {
    awaitPromise: true,
    functionDeclaration: `function () {
      this.scrollIntoView({ block: "nearest", inline: "nearest" });
      const rect = this.getBoundingClientRect();
      return { bottom: rect.bottom, height: rect.height, left: rect.left, right: rect.right, top: rect.top, width: rect.width };
    }`,
    objectId,
    returnByValue: true,
  });
  await client.send("Runtime.releaseObject", { objectId });
  const rect = rectResult.result?.value;
  assert.ok(rect && rect.width > 40 && rect.height > 8, "Prediction option has no visible pointer target");
  const point = {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
  };
  const hit = await client.send("DOM.getNodeForLocation", {
    includeUserAgentShadowDOM: true,
    x: Math.round(point.x),
    y: Math.round(point.y),
  });
  assert.ok(hit.backendNodeId, "Prediction option pointer target is not hit-testable");
  await client.send("Input.dispatchMouseEvent", { button: "none", buttons: 0, pointerType: "mouse", type: "mouseMoved", ...point });
  await delay(100);
  await client.send("Input.dispatchMouseEvent", { button: "left", buttons: 1, clickCount: 1, pointerType: "mouse", type: "mousePressed", ...point });
  await delay(50);
  await client.send("Input.dispatchMouseEvent", { button: "left", buttons: 0, clickCount: 1, pointerType: "mouse", type: "mouseReleased", ...point });
}

async function selectedVenueState(client) {
  return evaluate(client, `(() => {
    const form = document.querySelector(".top-venue-form");
    const status = form?.querySelector(".venue-place-status");
    const save = form?.querySelector('button[type="submit"]');
    return {
      form: Boolean(form),
      messageVisible: Boolean(status?.querySelector("small")?.textContent.trim()),
      saveDisabled: !save || save.hasAttribute("disabled"),
      selected: Boolean(status?.classList.contains("selected") && status.textContent.includes("Dirección verificada")),
      statusError: Boolean(status?.classList.contains("error")),
      statusText: String(status?.textContent || "").trim().replace(/\s+/g, " ").slice(0, 180),
    };
  })()`);
}

async function googleScriptFingerprint(client) {
  return evaluate(client, `(async () => {
    const scripts = [...document.scripts].filter((script) => script.src.startsWith("https://maps.googleapis.com/maps/api/js"));
    if (scripts.length !== 1) return { count: scripts.length, fingerprint: "" };
    const key = new URL(scripts[0].src).searchParams.get("key") || "";
    const bytes = new TextEncoder().encode(key);
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    return { count: 1, fingerprint: [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("") };
  })()`);
}

async function waitForCanonicalGroup(service, groupId, predicate, label) {
  let last;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const result = await service.from("pachanga_groups")
      .select("id,payload,payload_revision,updated_at")
      .eq("id", groupId)
      .single();
    if (result.error) throw result.error;
    last = result.data;
    if (predicate(last)) return last;
    await delay(150);
  }
  throw new Error(`GOOGLE_PLACES_CANONICAL_READBACK_TIMEOUT:${label}:${last?.payload_revision ?? "none"}`);
}

function sanitizeDiagnostic(value) {
  return String(value ?? "")
    .replace(/([?&]key=)[^&\s]+/gi, "$1[redacted]")
    .replace(/[A-Za-z0-9_-]{32,}/g, "[redacted]")
    .replace(/[\w.+-]+@[\w.-]+/g, "[redacted-email]")
    .slice(0, 500);
}

async function bestEffort(action) {
  try {
    await action();
  } catch {
    // The isolated Supabase branch is destroyed after all evidence is collected.
  }
}

const chromePath = process.env.CHROME_PATH ?? findChromePath();
if (!chromePath) throw new Error("GOOGLE_PLACES_CHROME_NOT_FOUND");

const { publishableKey, serviceRoleKey } = loadEphemeralApiKeys();
const supabaseUrl = `https://${env.projectRef}.supabase.co`;
const service = supabaseClient(supabaseUrl, serviceRoleKey);
const ownerClient = supabaseClient(supabaseUrl, publishableKey);
const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const account = {
  email: `places166-${runId}@pachangasiq.test`,
  id: randomUUID(),
  password: `Places166-${randomUUID()}-Qa!`,
};
const chromeDir = mkdtempSync(join(tmpdir(), "pachangas-places166-chrome-"));
const port = 9400 + Math.floor(Math.random() * 300);
let browser;
let browserClient;
let groupId = "";
let initialFlags;
let flagsChanged = false;
let session;
let report;
let settingsClient = ownerClient;
let separateSettingsClient = false;
const consoleErrors = [];
const expectedOfflineConsoleErrors = [];
const runtimeFailures = [];
const networkEvidence = [];
let intentionalOffline = false;
let touchInputEnabled = false;

function observeBrowserDiagnostics(client) {
  return client.onEvent((message) => {
    if (message.method === "Runtime.consoleAPICalled" && message.params.type === "error") {
      const diagnostic = (message.params.args ?? []).map((entry) => entry.value ?? entry.description ?? "").join(" ");
      const sanitized = sanitizeDiagnostic(diagnostic);
      if (intentionalOffline && /<gmp-place-autocomplete>.*network request error.*xhr error/i.test(sanitized)) {
        expectedOfflineConsoleErrors.push(sanitized);
      } else {
        consoleErrors.push(sanitized);
      }
    }
    if (message.method === "Runtime.exceptionThrown") {
      runtimeFailures.push(sanitizeDiagnostic(message.params.exceptionDetails?.exception?.description ?? "Uncaught exception"));
    }
    if (message.method === "Network.responseReceived") {
      try {
        const responseUrl = new URL(message.params.response.url);
        const relevantSupabasePath = responseUrl.hostname === `${env.projectRef}.supabase.co`
          && (/^\/auth\/v1\//.test(responseUrl.pathname) || /^\/rest\/v1\/(pachanga_group_members|pachanga_groups)/.test(responseUrl.pathname));
        const relevantGooglePath = /(^|\.)(maps|places)\.googleapis\.com$/.test(responseUrl.hostname);
        if ((message.params.response.status >= 400 || relevantSupabasePath || relevantGooglePath) && networkEvidence.length < 120) {
          networkEvidence.push({
            host: responseUrl.hostname,
            path: responseUrl.pathname,
            status: message.params.response.status,
          });
        }
      } catch {
        // Browser-internal responses without a standard URL are not useful here.
      }
    }
  });
}

try {
  const created = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password: account.password,
    user_metadata: { qaFixture: "GOOGLE_PLACES_ISSUE_166", runId },
  });
  if (created.error) throw created.error;

  const signedIn = await ownerClient.auth.signInWithPassword({ email: account.email, password: account.password });
  if (signedIn.error) throw signedIn.error;
  session = signedIn.data.session;
  assert.equal(session.user.id, account.id);

  initialFlags = await rpcOk(ownerClient, "get_pachanga_social_team_feature_flags_v1", {});
  const requiredFlags = [
    "socialProfileFoundationEnabled",
    "socialProfileIndependentWriteEnabled",
    "socialTeamCreationEnabled",
    "socialTeamHomeV3fEnabled",
  ];
  if (requiredFlags.some((key) => initialFlags[key] !== true)) {
    const platformAccess = await rpcOk(service, "get_pachanga_platform_access_service_v1", {
      target_user_id: account.id,
    });
    if (platformAccess?.role !== "platform_owner") {
      const listedUsers = await service.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (listedUsers.error) throw listedUsers.error;
      let priorPlatformOwner = null;
      for (const candidate of listedUsers.data.users) {
        if (candidate.id === account.id || candidate.user_metadata?.qaFixture !== "GOOGLE_PLACES_ISSUE_166" || !candidate.email) continue;
        const candidateAccess = await rpcOk(service, "get_pachanga_platform_access_service_v1", {
          target_user_id: candidate.id,
        });
        if (candidateAccess?.role === "platform_owner") {
          priorPlatformOwner = candidate;
          break;
        }
      }
      if (priorPlatformOwner?.email) {
        const settingsPassword = `Places166-${randomUUID()}-Settings!`;
        const updated = await service.auth.admin.updateUserById(priorPlatformOwner.id, { password: settingsPassword });
        if (updated.error) throw updated.error;
        settingsClient = supabaseClient(supabaseUrl, publishableKey);
        const settingsSignIn = await settingsClient.auth.signInWithPassword({
          email: priorPlatformOwner.email,
          password: settingsPassword,
        });
        if (settingsSignIn.error) throw settingsSignIn.error;
        separateSettingsClient = true;
      } else {
        await rpcOk(service, "bootstrap_pachanga_platform_owner_v1", {
          operation_id: randomUUID(),
          reason: "Google Places issue 166 isolated Preview fixture",
          target_user_id: account.id,
        });
      }
    }
    await rpcOk(settingsClient, "command_pachanga_social_team_settings_v1", {
      client_metadata: metadata("places166-staging-flags"),
      expected_revision: initialFlags.confirmedRevision,
      operation_id: randomUUID(),
      payload: {
        demoSocialTeamJourneyEnabled: true,
        socialProfileFoundationEnabled: true,
        socialProfileIndependentWriteEnabled: true,
        socialTeamCreationEnabled: true,
        socialTeamHomeV3fEnabled: true,
        socialTeamInvitationV2Enabled: true,
        socialTeamMembershipV2Enabled: true,
      },
    });
    flagsChanged = true;
  }

  await rpcOk(ownerClient, "command_pachanga_social_profile_v1", {
    action: "profile.create",
    client_metadata: metadata("places166-profile"),
    expected_revision: 0,
    operation_id: randomUUID(),
    payload: {
      approximateTime: "20:00-22:00",
      displayName: `Places QA ${runId}`,
      generalArea: "Barcelona",
      preferredModality: "futbol7",
      primaryPosition: "Mediocentro / pivote",
      usualDays: ["M"],
    },
  });

  const team = await rpcOk(ownerClient, "command_pachanga_social_team_v1", {
    action: "team.create",
    client_metadata: metadata("places166-team"),
    expected_revision: 0,
    operation_id: randomUUID(),
    payload: {
      generalArea: "Barcelona",
      modality: "futbol7",
      name: `Places QA ${runId}`,
      shieldKey: "team.shield.shape.classic_iq",
      targetPlayerCount: 14,
    },
  });
  groupId = team.groupId;
  assert.ok(groupId);

  const initialGroup = await service.from("pachanga_groups")
    .select("payload_revision")
    .eq("id", groupId)
    .single();
  if (initialGroup.error) throw initialGroup.error;

  browser = spawn(chromePath, [
    "--headless=new",
    "--disable-dev-shm-usage",
    "--disable-extensions",
    "--no-default-browser-check",
    "--no-first-run",
    "--lang=es-ES",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${chromeDir}`,
    "about:blank",
  ], { stdio: "ignore" });
  await waitForJson(`http://127.0.0.1:${port}/json/version`);
  browserClient = await openPage(port);
  await Promise.all([
    browserClient.send("Accessibility.enable"),
    browserClient.send("DOM.enable"),
    browserClient.send("Network.enable"),
    browserClient.send("Page.enable"),
    browserClient.send("Runtime.enable"),
  ]);
  await installPreviewBypass(browserClient, (error) => {
    runtimeFailures.push(sanitizeDiagnostic(error instanceof Error ? error.message : String(error)));
  });
  observeBrowserDiagnostics(browserClient);

  await setViewport(browserClient, { height: 900, mobile: false, width: 1440 });
  if (shareTarget) {
    await navigate(browserClient, shareTarget.toString());
    await waitForCondition(
      browserClient,
      `location.hostname === ${JSON.stringify(previewTarget.hostname)}`,
      "vercel-protection-cookie",
    );
  }
  await navigate(browserClient, new URL("/", previewTarget).toString());
  const authStorageKey = `sb-${env.projectRef}-auth-token`;
  await evaluate(browserClient, `localStorage.setItem(${JSON.stringify(authStorageKey)}, ${JSON.stringify(JSON.stringify(session))})`);

  const teamUrl = new URL(`/?grupo=${encodeURIComponent(groupId)}&mobile=partido`, previewTarget).toString();
  await navigate(browserClient, teamUrl);
  try {
    await waitForCondition(browserClient, `Boolean(document.querySelector("main[data-team-state='member']"))`, "team-member-shell");
  } catch (error) {
    const diagnostic = await teamBootstrapDiagnostic(browserClient, authStorageKey);
    throw new Error(`${error instanceof Error ? error.message : "GOOGLE_PLACES_PREVIEW_TEAM_BOOTSTRAP_FAILED"}:${JSON.stringify({
      consoleErrors: consoleErrors.filter(Boolean).slice(-5),
      diagnostic,
      networkEvidence: networkEvidence.slice(-12),
      runtimeFailures: runtimeFailures.filter(Boolean).slice(-5),
    })}`);
  }
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-view='overview']"))`, "match-overview");

  await clickByText(browserClient, "Crear partido", "[data-view='overview'] button");
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-view='wizard']"))`, "quick-match-wizard");
  await clickByText(browserClient, "Añadir campo", "[data-view='wizard'] button");
  await waitForCondition(browserClient, `Boolean(document.querySelector(".top-venue-form gmp-place-autocomplete"))`, "places-widget");
  await observePlacesEvents(browserClient);

  const scriptIdentity = await googleScriptFingerprint(browserClient);
  assert.equal(scriptIdentity.count, 1, "Preview must load one Google Maps script");
  assert.equal(scriptIdentity.fingerprint, env.expectedKeyFingerprint, "Preview key fingerprint mismatch");
  assert.notEqual(scriptIdentity.fingerprint, env.productionKeyFingerprint, "Preview reused the production Google key");

  await typeWidgetQuery(browserClient, env.query);
  let options = await waitForPredictionOptions(browserClient);
  const observedPredictionCount = options.length;
  assert.ok(observedPredictionCount > 0);
  assert.equal((await selectedVenueState(browserClient)).saveDisabled, true, "Free text enabled field persistence");

  const viewportResults = [];
  const viewports = [
    { height: 900, label: "desktop-1440", mobile: false, width: 1440 },
    { height: 720, label: "desktop-1280", mobile: false, width: 1280 },
    { height: 768, label: "tablet-1024", mobile: true, width: 1024 },
    { height: 844, label: "portrait-390", mobile: true, width: 390 },
    { height: 800, label: "portrait-360", mobile: true, width: 360 },
    { height: 390, label: "landscape-844", mobile: true, width: 844 },
  ];
  for (const viewport of viewports) {
    await openVenueFormAtViewport(browserClient, viewport, teamUrl);
    await typeWidgetQuery(browserClient, env.query);
    const viewportOptions = await waitForPredictionOptions(browserClient, viewport.label);
    const metrics = await evaluate(browserClient, `(() => {
      const doc = document.documentElement;
      const body = document.body;
      const widget = document.querySelector("gmp-place-autocomplete");
      const save = document.querySelector('.top-venue-form button[type="submit"]');
      const widgetRect = widget?.getBoundingClientRect();
      const saveRect = save?.getBoundingClientRect();
      return {
        displayMode: matchMedia("(display-mode: standalone)").matches ? "standalone" : "browser",
        overflow: Math.max(doc.scrollWidth, body.scrollWidth) - Math.max(doc.clientWidth, innerWidth),
        saveVisible: Boolean(saveRect && saveRect.width > 0 && saveRect.height > 0),
        widgetVisible: Boolean(widgetRect && widgetRect.width > 0 && widgetRect.height > 0),
      };
    })()`);
    assert.ok(metrics.widgetVisible, `${viewport.label}: widget hidden`);
    assert.ok(metrics.saveVisible, `${viewport.label}: save control hidden`);
    assert.ok(metrics.overflow <= 2, `${viewport.label}: root overflow ${metrics.overflow}`);
    viewportResults.push({ label: viewport.label, options: viewportOptions.length, overflow: Math.round(metrics.overflow) });
  }

  const pwaChromeDir = mkdtempSync(join(tmpdir(), "pachangas-places166-pwa-"));
  const pwaPort = 9800 + Math.floor(Math.random() * 200);
  let pwaBrowser;
  let pwaClient;
  try {
    pwaBrowser = spawn(chromePath, [
      "--disable-dev-shm-usage",
      "--disable-extensions",
      "--no-default-browser-check",
      "--no-first-run",
      "--lang=es-ES",
      "--window-position=-2000,-2000",
      "--window-size=390,844",
      `--remote-debugging-port=${pwaPort}`,
      `--user-data-dir=${pwaChromeDir}`,
      `--app=${previewTarget.origin}`,
    ], { stdio: "ignore" });
    await waitForJson(`http://127.0.0.1:${pwaPort}/json/version`);
    pwaClient = await openExistingPage(pwaPort);
    await Promise.all([
      pwaClient.send("Accessibility.enable"),
      pwaClient.send("DOM.enable"),
      pwaClient.send("Network.enable"),
      pwaClient.send("Page.enable"),
      pwaClient.send("Runtime.enable"),
    ]);
    await installPreviewBypass(pwaClient, (error) => {
      runtimeFailures.push(sanitizeDiagnostic(error instanceof Error ? error.message : String(error)));
    });
    observeBrowserDiagnostics(pwaClient);
    await setViewport(pwaClient, { displayMode: "standalone", height: 844, mobile: true, width: 390 });
    await navigate(pwaClient, new URL("/", previewTarget).toString());
    await evaluate(pwaClient, `localStorage.setItem(${JSON.stringify(authStorageKey)}, ${JSON.stringify(JSON.stringify(session))})`);
    await openVenueFormAtViewport(
      pwaClient,
      { displayMode: "standalone", height: 844, label: "pwa-portrait-390", mobile: true, width: 390 },
      teamUrl,
    );
    await typeWidgetQuery(pwaClient, env.query);
    assert.ok((await waitForPredictionOptions(pwaClient, "pwa-portrait-390")).length > 0);
    assert.equal(await evaluate(pwaClient, `matchMedia("(display-mode: standalone)").matches`), true);
    const workerState = await evaluate(pwaClient, `(async () => {
      if (!("serviceWorker" in navigator)) return { ready: false, supported: false };
      const registrations = await navigator.serviceWorker.getRegistrations().catch(() => []);
      const ready = registrations.some((registration) => Boolean(registration.active));
      return {
        controlled: Boolean(navigator.serviceWorker.controller),
        displayMode: document.documentElement.dataset.displayMode || "",
        ready,
        registrations: registrations.map((registration) => ({
          active: registration.active?.state || "",
          installing: registration.installing?.state || "",
          scopePath: new URL(registration.scope).pathname,
          waiting: registration.waiting?.state || "",
        })),
        secureContext: window.isSecureContext,
        supported: true,
      };
    })()`);
    assert.equal(workerState.supported, true, "Standalone app context does not expose Service Worker support");
    assert.equal(workerState.secureContext, true, "Standalone app context is not secure");
    assert.equal((await selectedVenueState(pwaClient)).saveDisabled, true);
    await openVenueFormAtViewport(
      pwaClient,
      { displayMode: "standalone", height: 390, label: "pwa-landscape-844", mobile: true, width: 844 },
      teamUrl,
    );
    await typeWidgetQuery(pwaClient, env.query);
    assert.ok((await waitForPredictionOptions(pwaClient, "pwa-landscape-844")).length > 0);
    assert.equal(await evaluate(pwaClient, `matchMedia("(display-mode: standalone)").matches`), true);
    assert.ok((await elementState(pwaClient, "gmp-place-autocomplete"))?.width > 0);
  } finally {
    if (pwaClient) pwaClient.close();
    if (pwaBrowser) {
      pwaBrowser.kill();
      for (let attempt = 0; attempt < 20 && pwaBrowser.exitCode === null; attempt += 1) await delay(100);
    }
    rmSync(pwaChromeDir, { force: true, recursive: true });
  }

  const browserWorkerState = await evaluate(browserClient, `(async () => {
    if (!("serviceWorker" in navigator)) return { ready: false, supported: false };
    const registration = await Promise.race([
      navigator.serviceWorker.ready,
      new Promise((resolve) => setTimeout(() => resolve(null), 15000)),
    ]);
    const registrations = await navigator.serviceWorker.getRegistrations().catch(() => []);
    return {
      active: registration?.active?.state || "",
      controlled: Boolean(navigator.serviceWorker.controller),
      ready: Boolean(registration?.active),
      registrationCount: registrations.length,
      supported: true,
    };
  })()`);
  assert.equal(browserWorkerState.ready, true, `Preview Service Worker did not become ready: ${JSON.stringify(browserWorkerState)}`);
  assert.equal(browserWorkerState.registrationCount, 1, "Preview must keep one Service Worker registration");

  await openVenueFormAtViewport(
    browserClient,
    { height: 900, label: "desktop-selection", mobile: false, width: 1440 },
    teamUrl,
  );
  await typeWidgetQuery(browserClient, env.query);
  await waitForPredictionOptions(browserClient);
  await selectPredictionByKeyboard(browserClient);
  await waitForCondition(browserClient, `(globalThis.__places166?.select ?? 0) >= 1`, "keyboard-gmp-select");
  try {
    await waitForCondition(browserClient, `(document.querySelector(".venue-place-status")?.textContent || "").includes("Dirección verificada")`, "keyboard-selection-details");
  } catch (error) {
    throw new Error(`${error instanceof Error ? error.message : "GOOGLE_PLACES_KEYBOARD_SELECTION_DETAILS_FAILED"}:${JSON.stringify({
      consoleErrors: consoleErrors.filter(Boolean).slice(-8),
      events: await evaluate(browserClient, `globalThis.__places166 ?? { error: 0, select: 0 }`),
      networkEvidence: networkEvidence.slice(-16),
      runtimeFailures: runtimeFailures.filter(Boolean).slice(-8),
      selection: await selectedVenueState(browserClient),
    })}`);
  }
  let selected = await selectedVenueState(browserClient);
  assert.equal(selected.selected, true);
  assert.equal(selected.saveDisabled, false);
  const keyboardSelectionEventCounts = await evaluate(browserClient, `globalThis.__places166 ?? { error: 0, select: 0 }`);
  assert.ok(keyboardSelectionEventCounts.select >= 1, "Keyboard selection event was not retained");

  await focusWidget(browserClient);
  await clientInsertText(browserClient, " modificada");
  await waitForCondition(browserClient, `document.querySelector('.top-venue-form button[type="submit"]')?.hasAttribute("disabled")`, "selection-invalidation");
  selected = await selectedVenueState(browserClient);
  assert.equal(selected.selected, false);
  assert.equal(selected.saveDisabled, true);

  intentionalOffline = true;
  await browserClient.send("Network.emulateNetworkConditions", {
    connectionType: "none",
    downloadThroughput: 0,
    latency: 0,
    offline: true,
    uploadThroughput: 0,
  });
  await typeWidgetQuery(browserClient, "Polideportivo Barcelona");
  await waitForCondition(browserClient, `navigator.onLine === false`, "offline-state");
  await delay(1500);
  await waitForCondition(browserClient, `(globalThis.__places166?.error ?? 0) >= 1`, "offline-gmp-error");
  selected = await selectedVenueState(browserClient);
  assert.equal(selected.saveDisabled, true, "Offline search enabled field persistence");
  assert.equal(selected.selected, false, "Offline search retained a confirmed selection");
  const offlineEventCounts = await evaluate(browserClient, `globalThis.__places166 ?? { error: 0, select: 0 }`);

  await browserClient.send("Network.emulateNetworkConditions", {
    connectionType: "wifi",
    downloadThroughput: -1,
    latency: 0,
    offline: false,
    uploadThroughput: -1,
  });
  await waitForCondition(browserClient, `navigator.onLine === true`, "online-restored");
  intentionalOffline = false;
  await openVenueFormAtViewport(
    browserClient,
    { height: 900, label: "desktop-pointer-selection", mobile: false, width: 1440 },
    teamUrl,
  );
  await typeWidgetQuery(browserClient, env.query);
  options = await waitForPredictionOptions(browserClient);
  await selectPredictionByPointer(browserClient, options[0]);
  await waitForCondition(browserClient, `(globalThis.__places166?.select ?? 0) >= 1`, "pointer-gmp-select");
  await waitForCondition(browserClient, `(document.querySelector(".venue-place-status")?.textContent || "").includes("Dirección verificada")`, "pointer-selection-details");
  selected = await selectedVenueState(browserClient);
  assert.equal(selected.selected, true);
  assert.equal(selected.saveDisabled, false);
  const pointerSelectionEventCounts = await evaluate(browserClient, `globalThis.__places166 ?? { error: 0, select: 0 }`);
  const selectionEventCounts = {
    error: keyboardSelectionEventCounts.error + offlineEventCounts.error + pointerSelectionEventCounts.error,
    select: keyboardSelectionEventCounts.select + pointerSelectionEventCounts.select,
  };
  assert.ok(selectionEventCounts.select >= 2, "Google Places did not emit both verified selection events");

  await clickByText(browserClient, "Guardar campo", ".top-venue-form button");
  await waitForCondition(browserClient, `!document.querySelector(".top-venue-form")`, "venue-form-close");

  const groupWithVenue = await waitForCanonicalGroup(
    service,
    groupId,
    (row) => Array.isArray(row.payload?.venues) && row.payload.venues.length === 1,
    "venue",
  );
  assert.ok(groupWithVenue.payload_revision > initialGroup.data.payload_revision);
  const venue = groupWithVenue.payload.venues[0];
  assert.ok(typeof venue.placeId === "string" && venue.placeId.trim());
  assert.ok(typeof venue.name === "string" && venue.name.trim());
  assert.ok(typeof venue.address === "string" && venue.address.trim());
  assert.ok(typeof venue.city === "string" && venue.city.trim());
  assert.match(String(venue.country ?? ""), /españa|spain/i);
  if (venue.lat != null || venue.lng != null) {
    assert.ok(Number.isFinite(Number(venue.lat)) && Number.isFinite(Number(venue.lng)));
  }
  assert.equal(Number(venue.defaultCost), 56);
  assert.equal(venue.kind, "futbol7");
  const placeIdHash = createHash("sha256").update(venue.placeId).digest("hex");

  await clickByText(
    browserClient,
    "Partidos",
    "nav[aria-label='Navegación principal'] button, nav[aria-label='Navegación principal'] a, nav[aria-label='Navegación principal móvil'] button, nav[aria-label='Navegación principal móvil'] a, aside[aria-label='Navegación de modo juego'] button, aside[aria-label='Navegación de modo juego'] a",
    false,
  );
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-view='overview']"))`, "overview-after-venue");
  await clickByText(browserClient, "Continuar", "[aria-label='Borradores de partido'] button");
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-view='wizard']"))`, "resume-wizard");
  assert.equal(await evaluate(browserClient, `(() => {
    const venueSelect = [...document.querySelectorAll("[data-view='wizard'] label")]
      .find((label) => String(label.childNodes[0]?.textContent || "").trim() === "Campo")
      ?.querySelector("select");
    return venueSelect?.value === ${JSON.stringify(venue.id)};
  })()`), true, "Resumed draft did not retain the canonical venue");
  await clickByText(browserClient, "Continuar", "[data-view='wizard'] footer button");
  await waitForCondition(browserClient, `document.querySelector("[data-view='wizard'] h1")?.textContent === "Jugadores y plazas"`, "wizard-step-two");
  await clickByText(browserClient, "Continuar", "[data-view='wizard'] footer button");
  await waitForCondition(browserClient, `document.querySelector("[data-view='wizard'] h1")?.textContent === "Revisar y crear"`, "wizard-step-three");
  await clickByText(browserClient, "Crear partido", "[data-view='wizard'] footer button");
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-official-match-hub='v3b']"))`, "canonical-match-detail");

  const groupWithMatch = await waitForCanonicalGroup(
    service,
    groupId,
    (row) => Array.isArray(row.payload?.matches)
      && row.payload.matches.some((match) => match.configured === true && match.venueId === venue.id),
    "match",
  );
  const canonicalMatch = groupWithMatch.payload.matches.find((match) => match.configured === true && match.venueId === venue.id);
  assert.ok(canonicalMatch);
  assert.equal(canonicalMatch.place, venue.name);
  assert.ok(groupWithMatch.payload_revision > groupWithVenue.payload_revision);

  await evaluate(browserClient, `(() => {
    const keep = ${JSON.stringify(authStorageKey)};
    for (const key of Object.keys(localStorage)) if (key !== keep) localStorage.removeItem(key);
    sessionStorage.clear();
  })()`);
  await navigate(browserClient, teamUrl);
  await waitForCondition(browserClient, `Boolean(document.querySelector("main[data-team-state='member']"))`, "canonical-reload-member");
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-view='overview']"))`, "canonical-reload-overview");
  await waitForCondition(browserClient, `(() => [...document.querySelectorAll("[data-view='overview'] article[data-match-state] > button")]
    .some((card) => String(card.textContent || "").includes(${JSON.stringify(venue.name)})))()`, "canonical-venue-card");
  const opened = await evaluate(browserClient, `(() => {
    const card = [...document.querySelectorAll("[data-view='overview'] article[data-match-state] > button")]
      .find((entry) => String(entry.textContent || "").includes(${JSON.stringify(venue.name)}));
    if (!card) return false;
    card.click();
    return true;
  })()`);
  assert.equal(opened, true);
  await waitForCondition(browserClient, `Boolean(document.querySelector("[data-official-match-hub='v3b']"))`, "reloaded-match-open");
  assert.equal(await evaluate(browserClient, `document.body.innerText.includes(${JSON.stringify(venue.name)})`), true);

  const finalReadback = await service.from("pachanga_groups")
    .select("payload,payload_revision")
    .eq("id", groupId)
    .single();
  if (finalReadback.error) throw finalReadback.error;
  assert.equal(finalReadback.data.payload.venues.length, 1);
  assert.equal(finalReadback.data.payload.matches.filter((match) => match.configured).length, 1);
  assert.equal(finalReadback.data.payload.venues[0].placeId, venue.placeId);
  assert.equal(finalReadback.data.payload.matches[0].venueId, venue.id);

  const unexpectedRuntimeFailures = runtimeFailures.filter(Boolean);
  assert.deepEqual(unexpectedRuntimeFailures, [], `Runtime failures: ${unexpectedRuntimeFailures.join(" | ")}`);
  const relevantConsoleErrors = consoleErrors.filter((message) => (
    message
    && !/ERR_INTERNET_DISCONNECTED|Failed to load resource/i.test(message)
  ));
  assert.deepEqual(relevantConsoleErrors, [], `Unexpected console errors: ${relevantConsoleErrors.join(" | ")}`);

  report = {
    auth: "SYNTHETIC_REGISTERED_OWNER",
    canonicalReadback: "VENUE_AND_MATCH_PASS",
    cleanup: "ISOLATED_BRANCH_DESTRUCTION_REQUIRED",
    coordinatesPresent: Number.isFinite(Number(venue.lat)) && Number.isFinite(Number(venue.lng)),
    errors: "OFFLINE_FAIL_CLOSED",
    googleEvents: { gmpError: selectionEventCounts.error, gmpSelect: selectionEventCounts.select },
    keyboard: "PASS",
    locality: "Barcelona",
    offlineConsoleErrors: expectedOfflineConsoleErrors.length,
    placeIdHash,
    pointer: "PASS",
    predictionCountLowerBound: observedPredictionCount,
    previewKeyFingerprint: scriptIdentity.fingerprint,
    productionKeySeparated: true,
    pwaEmulation: "PORTRAIT_AND_LANDSCAPE_PASS",
    query: env.query,
    reload: "LOCAL_READ_CACHE_CLEARED_CANONICAL_PASS",
    responsive: viewportResults,
    sourceAuthority: "OFFICIAL_UI_PLUS_EXISTING_RPC",
    status: "GOOGLE_PLACES_PREVIEW_SELECTION_PASS",
  };
} finally {
  if (browserClient) browserClient.close();
  if (browser) {
    browser.kill();
    for (let attempt = 0; attempt < 20 && browser.exitCode === null; attempt += 1) await delay(100);
  }
  rmSync(chromeDir, { force: true, recursive: true });

  if (flagsChanged && initialFlags) {
    await bestEffort(async () => {
      const current = await rpcOk(settingsClient, "get_pachanga_social_team_feature_flags_v1", {});
      await rpcOk(settingsClient, "command_pachanga_social_team_settings_v1", {
        client_metadata: metadata("places166-restore-flags"),
        expected_revision: current.confirmedRevision,
        operation_id: randomUUID(),
        payload: {
          demoSocialTeamJourneyEnabled: initialFlags.demoSocialTeamJourneyEnabled,
          socialProfileFoundationEnabled: initialFlags.socialProfileFoundationEnabled,
          socialProfileIndependentWriteEnabled: initialFlags.socialProfileIndependentWriteEnabled,
          socialTeamCreationEnabled: initialFlags.socialTeamCreationEnabled,
          socialTeamHomeV3fEnabled: initialFlags.socialTeamHomeV3fEnabled,
          socialTeamInvitationV2Enabled: initialFlags.socialTeamInvitationV2Enabled,
          socialTeamMembershipV2Enabled: initialFlags.socialTeamMembershipV2Enabled,
        },
      });
    });
  }
  if (groupId) {
    await bestEffort(() => service.from("pachanga_groups").delete().eq("id", groupId));
  }
  await bestEffort(() => service.from("pachanga_social_player_profiles_v1").delete().eq("user_id", account.id));
  await bestEffort(() => ownerClient.auth.signOut({ scope: "local" }));
  if (separateSettingsClient) await bestEffort(() => settingsClient.auth.signOut({ scope: "local" }));
  await bestEffort(() => ownerClient.realtime.disconnect());
  if (separateSettingsClient) await bestEffort(() => settingsClient.realtime.disconnect());
  await bestEffort(() => service.auth.admin.deleteUser(account.id));
}

assert.ok(report, "Google Places Preview E2E did not complete");
process.stdout.write(`${JSON.stringify(report)}\n`);

async function clientInsertText(client, text) {
  await client.send("Input.insertText", { text });
}
