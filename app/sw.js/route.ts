import { SERVICE_WORKER_VERSION } from "../client-version-contract";
import { buildServiceWorkerSource } from "../service-worker-source";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  return new Response(buildServiceWorkerSource(SERVICE_WORKER_VERSION), {
    headers: {
      "Cache-Control": "no-cache, no-store, must-revalidate",
      "Content-Type": "application/javascript; charset=utf-8",
      "Service-Worker-Allowed": "/",
    },
  });
}
