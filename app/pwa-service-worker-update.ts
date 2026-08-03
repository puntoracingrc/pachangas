import { V1_UNVERSIONED, classifyClientVersion } from "./client-version-contract";

type WaitingWorker = {
  postMessage(message: unknown, transfer?: Transferable[]): void;
};

type WaitingRegistration = {
  waiting: WaitingWorker | null;
};

export async function serviceWorkerVersion(worker: WaitingWorker | null, timeoutMs = 800) {
  if (!worker || typeof MessageChannel === "undefined") return V1_UNVERSIONED;

  return new Promise<string>((resolve) => {
    const channel = new MessageChannel();
    const timeout = setTimeout(() => resolve(V1_UNVERSIONED), timeoutMs);
    channel.port1.onmessage = (event: MessageEvent<{ serviceWorkerVersion?: unknown }>) => {
      clearTimeout(timeout);
      const version = typeof event.data?.serviceWorkerVersion === "string" ? event.data.serviceWorkerVersion : null;
      resolve(classifyClientVersion(version));
    };
    worker.postMessage({ type: "GET_VERSION" }, [channel.port2]);
  });
}

export async function activateWaitingServiceWorker(input: {
  getVersion?: (worker: WaitingWorker) => Promise<string>;
  pauseWrites: (paused: boolean) => void;
  registration: WaitingRegistration;
  setExpectedVersion: (version: string) => void;
  waitForWrites: () => Promise<boolean>;
}) {
  const waiting = input.registration.waiting;
  if (!waiting) return false;

  input.pauseWrites(true);
  const writesSettled = await input.waitForWrites();
  if (!writesSettled) {
    input.pauseWrites(false);
    return false;
  }

  const version = await (input.getVersion ?? serviceWorkerVersion)(waiting);
  input.setExpectedVersion(version);
  waiting.postMessage({ type: "SKIP_WAITING" });
  return true;
}

export function reloadOnceAfterControllerChange(input: {
  reload: () => void;
  serviceWorkerVersion: string;
  storage: Pick<Storage, "getItem" | "setItem">;
}) {
  const version = classifyClientVersion(input.serviceWorkerVersion);
  const key = `pachangas-sw-reloaded:${version}`;
  if (input.storage.getItem(key) === "yes") return false;
  input.storage.setItem(key, "yes");
  input.reload();
  return true;
}
