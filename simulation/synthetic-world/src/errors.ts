export function syntheticErrorMessage(error: unknown) {
  if (error instanceof Error) return error.stack ?? error.message;
  if (error && typeof error === "object") {
    const safe = Object.fromEntries(
      Object.entries(error).filter(([key]) => !/key|token|authorization|credential|secret/i.test(key)),
    );
    try {
      return JSON.stringify(safe, null, 2);
    } catch {
      return "Unserializable structured Synthetic World error";
    }
  }
  return String(error);
}
