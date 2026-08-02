const precacheUrls = [
  "/",
  "/manifest.webmanifest",
  "/favicon.svg",
  "/favicon-16.png",
  "/favicon-32.png",
  "/apple-touch-icon.png",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable-192.png",
  "/icon-maskable-512.png",
  "/icon-monochrome.svg",
  "/brand/pachangas-logo-hero.png",
  "/brand/pachangas-logo-wide.png",
];

export function buildServiceWorkerSource(version: string) {
  const encodedVersion = JSON.stringify(version);
  const encodedPrecache = JSON.stringify(precacheUrls);

  return `const SERVICE_WORKER_VERSION = ${encodedVersion};
const CACHE_NAME = "pachangas-iq-pwa-" + SERVICE_WORKER_VERSION.replace(/[^0-9A-Za-z.-]/g, "-");
const CACHE_PREFIX = "pachangas-iq-pwa-";
const APP_SHELL_URL = "/";
const MAX_RUNTIME_CACHE_ENTRIES = 120;
const PRECACHE_URLS = ${encodedPrecache};
const STATIC_DESTINATIONS = new Set(["font", "image", "manifest", "script", "style"]);
const STATIC_FILE_EXTENSIONS = /\\.(?:css|js|mjs|png|jpg|jpeg|webp|svg|ico|woff2?)$/i;
const LIVE_SERVICE_HOST_PARTS = ["supabase.co", "stripe.com", "googleapis.com", "google.com", "gstatic.com", "weather.googleapis.com"];
const CACHEABLE_NAVIGATION_PATHS = new Set(["/", "/aviso-legal", "/condiciones", "/condiciones-venta", "/cookies", "/manual", "/mercado", "/privacidad"]);

function isSameOrigin(url) {
  return url.origin === self.location.origin;
}

function isLiveServiceUrl(url) {
  return LIVE_SERVICE_HOST_PARTS.some((hostPart) => url.hostname === hostPart || url.hostname.endsWith("." + hostPart));
}

function isSensitivePath(pathname) {
  return pathname.startsWith("/api/") || pathname.startsWith("/auth/") || pathname.startsWith("/_next/data/");
}

function shouldCacheNavigation(url) {
  return isSameOrigin(url) && !url.search && !isSensitivePath(url.pathname) && CACHEABLE_NAVIGATION_PATHS.has(url.pathname);
}

function shouldCacheStaticRequest(request, url) {
  return isSameOrigin(url) && !isSensitivePath(url.pathname) && !url.search &&
    (url.pathname.startsWith("/_next/static/") || STATIC_DESTINATIONS.has(request.destination) || STATIC_FILE_EXTENSIONS.test(url.pathname));
}

async function trimRuntimeCache(cache) {
  const keys = await cache.keys();
  if (keys.length <= MAX_RUNTIME_CACHE_ENTRIES) return;
  await Promise.all(keys.slice(0, keys.length - MAX_RUNTIME_CACHE_ENTRIES).map((request) => cache.delete(request)));
}

async function networkFirstNavigation(request, preloadResponsePromise) {
  const url = new URL(request.url);
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = (await preloadResponsePromise) || (await fetch(request));
    if (response.ok && shouldCacheNavigation(url)) {
      await cache.put(request, response.clone());
      await trimRuntimeCache(cache);
    }
    return response;
  } catch {
    const cachedPage = await cache.match(request);
    return cachedPage || cache.match(APP_SHELL_URL);
  }
}

async function staleWhileRevalidate(request) {
  const cache = await caches.open(CACHE_NAME);
  const cachedResponse = await cache.match(request);
  const networkResponse = fetch(request).then((response) => {
    if (response.ok) {
      void cache.put(request, response.clone());
      void trimRuntimeCache(cache);
    }
    return response;
  }).catch(() => undefined);
  if (cachedResponse) return cachedResponse;
  return (await networkResponse) || Response.error();
}

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(Promise.all([
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME).map((key) => caches.delete(key)))),
    self.registration.navigationPreload?.enable?.(),
  ]).then(() => self.clients.claim()));
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (!isSameOrigin(url) || isSensitivePath(url.pathname) || isLiveServiceUrl(url)) return;
  if (request.mode === "navigate") {
    event.respondWith(networkFirstNavigation(request, event.preloadResponse));
    return;
  }
  if (shouldCacheStaticRequest(request, url)) event.respondWith(staleWhileRevalidate(request));
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "GET_VERSION") {
    event.ports?.[0]?.postMessage({ serviceWorkerVersion: SERVICE_WORKER_VERSION });
    return;
  }
  if (event.data?.type === "SKIP_WAITING") void self.skipWaiting();
});
`;
}
