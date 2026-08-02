import {
  CLIENT_UPDATE_REQUIRED,
  V1_UNVERSIONED,
  classifyClientVersion,
  clientVersionIsSupported,
  type ClientDisplayMode,
} from "./client-version-contract";
import type { ClientWriteTelemetryInput, ClientWriteTelemetryResult } from "./api/client-telemetry/_contract";

export const OFFLINE_WRITE_NOT_CONFIRMED = "OFFLINE_WRITE_NOT_CONFIRMED";
export const WRITE_CONFIRMATION_UNAVAILABLE = "WRITE_CONFIRMATION_UNAVAILABLE";
export const WRITE_PAUSED_FOR_UPDATE = "WRITE_PAUSED_FOR_UPDATE";

export type PwaWriteRejection = {
  code: string;
  message: string;
  operation: string;
  writeId: string;
};

export type PwaBridgeSnapshot = {
  activeWrites: number;
  clientVersion: string;
  lastErrorCode: string | null;
  minimumSupportedClientVersion: string | null;
  offline: boolean;
  serviceWorkerVersion: string;
  updateRequired: boolean;
  writesPaused: boolean;
};

type PolicyResponse = {
  clientClassification?: string;
  minimumSupportedClientVersion?: string;
  serverTime?: string;
  writeAllowed?: boolean;
};

type WriteBridgeDependencies = {
  clientVersion: string;
  displayMode: () => ClientDisplayMode;
  fetch: typeof fetch;
  isOnline: () => boolean;
  onRejected: (rejection: PwaWriteRejection) => void;
  policyUrl?: string;
  randomUUID: () => string;
  serviceWorkerVersion: string;
  telemetry: (record: ClientWriteTelemetryInput) => Promise<void> | void;
};

function rejectionResponse(code: string, message: string, status: number) {
  return new Response(JSON.stringify({ code, details: null, hint: null, message }), {
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json",
    },
    status,
  });
}

async function responseErrorCode(response: Response) {
  try {
    const body = (await response.clone().json()) as { code?: unknown };
    return typeof body.code === "string" ? body.code : `HTTP_${response.status}`;
  } catch {
    return `HTTP_${response.status}`;
  }
}

export class PwaWriteBridge {
  private activeWrites = 0;
  private lastErrorCode: string | null = null;
  private listeners = new Set<() => void>();
  private minimumSupportedClientVersion: string | null = null;
  private offline = false;
  private serviceWorkerVersion: string;
  private updateRequired = false;
  private writesPaused = false;

  constructor(private readonly dependencies: WriteBridgeDependencies) {
    this.serviceWorkerVersion = classifyClientVersion(dependencies.serviceWorkerVersion);
  }

  snapshot(): PwaBridgeSnapshot {
    return {
      activeWrites: this.activeWrites,
      clientVersion: classifyClientVersion(this.dependencies.clientVersion),
      lastErrorCode: this.lastErrorCode,
      minimumSupportedClientVersion: this.minimumSupportedClientVersion,
      offline: this.offline,
      serviceWorkerVersion: this.serviceWorkerVersion,
      updateRequired: this.updateRequired,
      writesPaused: this.writesPaused,
    };
  }

  subscribe(listener: () => void) {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  setServiceWorkerVersion(version: string | null | undefined) {
    this.serviceWorkerVersion = classifyClientVersion(version);
    this.emit();
  }

  setWritesPaused(paused: boolean) {
    this.writesPaused = paused;
    this.emit();
  }

  setOnlineState(online: boolean) {
    this.offline = !online;
    if (online && this.lastErrorCode === OFFLINE_WRITE_NOT_CONFIRMED) this.lastErrorCode = null;
    this.emit();
  }

  async waitForActiveWrites(timeoutMs = 30_000) {
    if (this.activeWrites === 0) return true;
    const startedAt = Date.now();

    return new Promise<boolean>((resolve) => {
      const stop = this.subscribe(() => {
        if (this.activeWrites === 0) {
          stop();
          resolve(true);
        }
      });
      const checkTimeout = () => {
        if (this.activeWrites === 0) return;
        if (Date.now() - startedAt >= timeoutMs) {
          stop();
          resolve(false);
          return;
        }
        setTimeout(checkTimeout, Math.min(100, timeoutMs));
      };
      setTimeout(checkTimeout, Math.min(100, timeoutMs));
    });
  }

  async refreshPolicy() {
    const clientVersion = classifyClientVersion(this.dependencies.clientVersion);
    const headers = new Headers({ Accept: "application/json" });
    if (clientVersion !== V1_UNVERSIONED) headers.set("X-Pachangas-Client-Version", clientVersion);
    headers.set("X-Pachangas-Display-Mode", this.dependencies.displayMode());
    headers.set("X-Pachangas-Service-Worker-Version", this.serviceWorkerVersion);

    const response = await this.dependencies.fetch(this.dependencies.policyUrl ?? "/api/client-policy", {
      cache: "no-store",
      headers,
      method: "GET",
    });
    if (!response.ok) throw new Error(`Client policy unavailable (${response.status})`);

    const policy = (await response.json()) as PolicyResponse;
    if (!policy.minimumSupportedClientVersion) throw new Error("Client policy is missing minimumSupportedClientVersion");
    const locallyAllowed = clientVersionIsSupported(clientVersion, policy.minimumSupportedClientVersion);
    const writeAllowed = policy.writeAllowed === true && locallyAllowed;

    this.minimumSupportedClientVersion = policy.minimumSupportedClientVersion;
    this.updateRequired = !writeAllowed;
    this.lastErrorCode = writeAllowed ? null : CLIENT_UPDATE_REQUIRED;
    this.offline = false;
    this.emit();
    return { ...policy, writeAllowed };
  }

  async executeWrite(
    operation: string,
    send: (metadataHeaders: Headers) => Promise<Response>,
  ): Promise<Response> {
    const writeId = this.dependencies.randomUUID();
    if (this.writesPaused) {
      return this.rejectWrite(operation, writeId, WRITE_PAUSED_FOR_UPDATE, "La app se está actualizando. El cambio no se ha enviado.", 409, "rejected-paused");
    }

    this.activeWrites += 1;
    this.emit();
    this.recordTelemetry(operation, writeId, "attempted");

    try {
      if (!this.dependencies.isOnline()) {
        this.offline = true;
        return this.rejectWrite(operation, writeId, OFFLINE_WRITE_NOT_CONFIRMED, "Sin conexión. El cambio no se ha confirmado.", 503, "rejected-offline");
      }

      let policy: PolicyResponse & { writeAllowed: boolean };
      try {
        policy = await this.refreshPolicy();
      } catch {
        this.offline = !this.dependencies.isOnline();
        return this.rejectWrite(
          operation,
          writeId,
          this.offline ? OFFLINE_WRITE_NOT_CONFIRMED : WRITE_CONFIRMATION_UNAVAILABLE,
          this.offline ? "Sin conexión. El cambio no se ha confirmado." : "No se ha podido confirmar la versión de la app. El cambio no se ha enviado.",
          503,
          this.offline ? "rejected-offline" : "network-error",
        );
      }

      if (!policy.writeAllowed) {
        return this.rejectWrite(operation, writeId, CLIENT_UPDATE_REQUIRED, "Actualiza Pachangas IQ antes de volver a guardar cambios.", 426, "rejected-update");
      }

      const metadataHeaders = new Headers({
        "X-Pachangas-Client-Version": classifyClientVersion(this.dependencies.clientVersion),
        "X-Pachangas-Display-Mode": this.dependencies.displayMode(),
        "X-Pachangas-Operation": operation,
        "X-Pachangas-Service-Worker-Version": this.serviceWorkerVersion,
        "X-Pachangas-Write-Id": writeId,
      });

      let response: Response;
      try {
        response = await send(metadataHeaders);
      } catch {
        this.offline = !this.dependencies.isOnline();
        return this.rejectWrite(
          operation,
          writeId,
          this.offline ? OFFLINE_WRITE_NOT_CONFIRMED : WRITE_CONFIRMATION_UNAVAILABLE,
          this.offline ? "Sin conexión. El cambio no se ha confirmado." : "La escritura no recibió confirmación del servidor.",
          503,
          this.offline ? "rejected-offline" : "network-error",
        );
      }

      if (!response.ok) {
        const code = await responseErrorCode(response);
        this.lastErrorCode = code;
        this.dependencies.onRejected({ code, message: "El servidor ha rechazado el cambio.", operation, writeId });
        this.recordTelemetry(operation, writeId, "rpc-error");
        this.emit();
        return response;
      }

      this.lastErrorCode = null;
      this.offline = false;
      this.recordTelemetry(operation, writeId, "confirmed");
      this.emit();
      return response;
    } finally {
      this.activeWrites = Math.max(0, this.activeWrites - 1);
      this.emit();
    }
  }

  private rejectWrite(
    operation: string,
    writeId: string,
    code: string,
    message: string,
    status: number,
    telemetryResult: ClientWriteTelemetryResult,
  ) {
    this.lastErrorCode = code;
    this.updateRequired = code === CLIENT_UPDATE_REQUIRED || this.updateRequired;
    this.dependencies.onRejected({ code, message, operation, writeId });
    this.recordTelemetry(operation, writeId, telemetryResult);
    this.emit();
    return rejectionResponse(code, message, status);
  }

  private recordTelemetry(operation: string, writeId: string, result: ClientWriteTelemetryResult) {
    void Promise.resolve(this.dependencies.telemetry({
      clientVersion: classifyClientVersion(this.dependencies.clientVersion),
      displayMode: this.dependencies.displayMode(),
      event: "write-intent",
      operation,
      result,
      serviceWorkerVersion: this.serviceWorkerVersion,
      writeId,
    })).catch(() => undefined);
  }

  private emit() {
    this.listeners.forEach((listener) => listener());
  }
}
