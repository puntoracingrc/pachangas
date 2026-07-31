const CACHE_NAME = "pachangas-iq-pwa-v1";
const APP_SHELL_URL = "/";
const PRECACHE_URLS = [
  APP_SHELL_URL,
  "/manifest.webmanifest",
  "/favicon.svg",
  "/favicon-16.png",
  "/favicon-32.png",
  "/apple-touch-icon.png",
  "/icon-192.png",
  "/icon-512.png",
  "/icon-maskable-192.png",
  "/icon-maskable-512.png",
];

const STATIC_DESTINATIONS = new Set(["font", "image", "manifest", "script", "style"]);
const CACHEABLE_NAVIGATION_PATHS = new Set([
  "/",
  "/aviso-legal",
  "/condiciones",
  "/condiciones-venta",
  "/cookies",
  "/manual",
  "/mercado",
  "/privacidad",
]);

function isSameOrigin(url) {
  return url.origin === self.location.origin;
}

function isSensitivePath(pathname) {
  return pathname.startsWith("/api/") || pathname.startsWith("/auth/") || pathname.startsWith("/_next/data/");
}

function shouldCacheNavigation(url) {
  return isSameOrigin(url) && !url.search && !isSensitivePath(url.pathname) && CACHEABLE_NAVIGATION_PATHS.has(url.pathname);
}

function shouldCacheStaticRequest(request, url) {
  return (
    isSameOrigin(url) &&
    !isSensitivePath(url.pathname) &&
    (url.pathname.startsWith("/_next/static/") || STATIC_DESTINATIONS.has(request.destination))
  );
}

async function networkFirstNavigation(request) {
  const url = new URL(request.url);
  const cache = await caches.open(CACHE_NAME);

  try {
    const response = await fetch(request);
    if (response.ok && shouldCacheNavigation(url)) {
      await cache.put(request, response.clone());
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
  const networkResponse = fetch(request)
    .then((response) => {
      if (response.ok) {
        void cache.put(request, response.clone());
      }
      return response;
    })
    .catch(() => undefined);

  if (cachedResponse) return cachedResponse;

  return (await networkResponse) || Response.error();
}

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (!isSameOrigin(url) || isSensitivePath(url.pathname)) return;

  if (request.mode === "navigate") {
    event.respondWith(networkFirstNavigation(request));
    return;
  }

  if (shouldCacheStaticRequest(request, url)) {
    event.respondWith(staleWhileRevalidate(request));
  }
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") {
    void self.skipWaiting();
  }
});
