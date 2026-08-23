export const GOOGLE_AUTH_RETURN_PARAM = "authReturn";

export function googleAuthEntryHref(returnPath: string) {
  const normalized = returnPath.startsWith("/") ? returnPath : "/";
  return `/?${GOOGLE_AUTH_RETURN_PARAM}=${encodeURIComponent(normalized)}`;
}

export function resolveGoogleAuthReturnHref(currentHref: string, expectedOrigin: string) {
  try {
    const current = new URL(currentHref, expectedOrigin);
    const fallback = new URL(current.href);
    fallback.searchParams.delete(GOOGLE_AUTH_RETURN_PARAM);

    if (current.origin !== expectedOrigin) return fallback.href;

    const requested = current.searchParams.get(GOOGLE_AUTH_RETURN_PARAM);
    if (!requested) return current.href;

    const target = new URL(requested, expectedOrigin);
    if (target.origin !== expectedOrigin || target.pathname === "/auth/google") return fallback.href;
    return target.href;
  } catch {
    return expectedOrigin;
  }
}
