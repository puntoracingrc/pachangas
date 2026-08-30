import { createHash } from "node:crypto";

export function demoWorldVerificationProjection(value: unknown): unknown {
  const uuidAliases = new Map<string, string>();
  const volatileTimestampKeys = new Set([
    "acceptedAt", "approvedAt", "assignedAt", "cancelledAt", "confirmedAt",
    "createdAt", "decidedAt", "generatedAt", "grantedAt", "opensAt",
    "continuityUntil", "graceEndsAt", "publishedAt", "rejectedAt", "renewalAt",
    "resolvedAt", "reviewedAt", "submittedAt", "updatedAt", "withdrawnAt",
  ]);
  const digestKey = /(?:authority[_-]?)?hash$|checksum|fingerprint|migration(?:Count|s)$/i;
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

  const visit = (input: unknown, key = ""): unknown => {
    if (Array.isArray(input)) return input.map((item) => visit(item));
    if (input && typeof input === "object") {
      return Object.fromEntries(Object.entries(input as Record<string, unknown>)
        .map(([entryKey, entryValue]) => [entryKey, visit(entryValue, entryKey)]));
    }
    if (digestKey.test(key)) return "<digest>";
    if (typeof input !== "string") return input;
    if (volatileTimestampKeys.has(key)) return "<server-time>";
    if (uuidPattern.test(input)) {
      const existing = uuidAliases.get(input);
      if (existing) return existing;
      const alias = `00000000-0000-4000-8000-${String(uuidAliases.size + 1).padStart(12, "0")}`;
      uuidAliases.set(input, alias);
      return alias;
    }
    return input.replace(/\?h=[0-9a-f]+$/i, "?h=<digest>");
  };

  return visit(value);
}

export function demoWorldVerificationProjectionHash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(demoWorldVerificationProjection(value))).digest("hex");
}
