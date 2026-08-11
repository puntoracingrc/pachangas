type ErrorLike = {
  code?: unknown;
  message?: unknown;
};

export const SERVICE_UNAVAILABLE_MESSAGE =
  "No podemos conectar con Pachangas IQ ahora. Revisa tu conexión y vuelve a intentarlo.";

function errorShape(value: unknown): ErrorLike {
  return value && typeof value === "object" ? value as ErrorLike : {};
}

export function userFacingError(
  value: unknown,
  fallback = "No se pudo completar la acción. Vuelve a intentarlo.",
) {
  const error = errorShape(value);
  const code = typeof error.code === "string" ? error.code : "";
  const raw = typeof error.message === "string"
    ? error.message.trim()
    : typeof value === "string" ? value.trim() : "";

  if (code === "PT409") {
    return "El contenido ha cambiado en otro dispositivo. Hemos recuperado la versión más reciente.";
  }
  if (/jwt|session|not authenticated|auth session missing/i.test(`${code} ${raw}`)) {
    return "Tu sesión ha caducado. Vuelve a entrar para continuar.";
  }
  if (/permission denied|row-level security|\brls\b|42501/i.test(`${code} ${raw}`)) {
    return "No tienes permiso para realizar esta acción.";
  }
  if (
    !raw
    || raw.length > 180
    || raw.includes("\n")
    || /supabase|postgrest|postgres|pgrst|rpc|sqlstate|relation |column |schema |fetch failed|failed to fetch|network ?error|network request failed|duplicate key|violates /i.test(raw)
  ) {
    return fallback;
  }
  return raw;
}
