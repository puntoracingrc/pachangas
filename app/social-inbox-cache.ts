import { normalizeSocialInboxSnapshot, type SocialInboxSnapshot } from "./social-inbox-contract";

const DATABASE_NAME = "pachangas-iq-private-read-models";
const DATABASE_VERSION = 1;
const STORE_NAME = "social-inbox-v1";
const CACHE_VERSION = "social-inbox-v1";

type CachedInbox = {
  cachedAt: string;
  key: string;
  snapshot: SocialInboxSnapshot;
  userId: string;
  version: string;
};

function cacheKey(userId: string) {
  return `${CACHE_VERSION}:${userId}`;
}

function openDatabase(): Promise<IDBDatabase | null> {
  if (typeof indexedDB === "undefined") return Promise.resolve(null);
  return new Promise((resolve) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE_NAME)) database.createObjectStore(STORE_NAME, { keyPath: "key" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(null);
    request.onblocked = () => resolve(null);
  });
}

export async function readSocialInboxCache(userId: string): Promise<CachedInbox | null> {
  const database = await openDatabase();
  if (!database) return null;
  return new Promise((resolve) => {
    const request = database.transaction(STORE_NAME, "readonly").objectStore(STORE_NAME).get(cacheKey(userId));
    request.onsuccess = () => {
      const row = request.result as Partial<CachedInbox> | undefined;
      const snapshot = normalizeSocialInboxSnapshot(row?.snapshot);
      resolve(row?.userId === userId && row.version === CACHE_VERSION && snapshot
        ? { cachedAt: String(row.cachedAt ?? ""), key: cacheKey(userId), snapshot, userId, version: CACHE_VERSION }
        : null);
      database.close();
    };
    request.onerror = () => {
      resolve(null);
      database.close();
    };
  });
}

export async function writeSocialInboxCache(userId: string, snapshot: SocialInboxSnapshot) {
  if (snapshot.view !== "pending" || snapshot.domain !== null) return;
  const database = await openDatabase();
  if (!database) return;
  await new Promise<void>((resolve) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put({
      cachedAt: new Date().toISOString(),
      key: cacheKey(userId),
      snapshot,
      userId,
      version: CACHE_VERSION,
    } satisfies CachedInbox);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => resolve();
    transaction.onabort = () => resolve();
  });
  database.close();
}
export async function clearSocialInboxCache() {
  const database = await openDatabase();
  if (!database) return;
  await new Promise<void>((resolve) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).clear();
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => resolve();
    transaction.onabort = () => resolve();
  });
  database.close();
}
