"use client";

import { useEffect, useSyncExternalStore } from "react";

export type ThemePreference = "system" | "light" | "dark";

type ThemeToggleProps = {
  compact?: boolean;
  defaultPreference?: ThemePreference;
};

const themePreferenceKey = "pachanga-iq-theme";
const themePreferenceEvent = "pachangas:theme-preference-change";
const themePreferenceOptions: Array<{ value: ThemePreference; label: string }> = [
  { value: "system", label: "Sistema" },
  { value: "light", label: "Claro" },
  { value: "dark", label: "Oscuro" },
];

export function resolveThemePreference(value: string | null, fallback: ThemePreference = "system"): ThemePreference {
  return value === "light" || value === "dark" || value === "system" ? value : fallback;
}

export function nextThemePreference(
  preference: ThemePreference,
  systemPreference: Exclude<ThemePreference, "system"> = "light",
): Exclude<ThemePreference, "system"> {
  const activePreference = preference === "system" ? systemPreference : preference;
  return activePreference === "dark" ? "light" : "dark";
}

function getStoredThemePreference(fallback: ThemePreference): ThemePreference {
  if (typeof window === "undefined") return fallback;

  try {
    return resolveThemePreference(window.localStorage.getItem(themePreferenceKey), fallback);
  } catch {
    return fallback;
  }
}

export function applyThemePreference(preference: ThemePreference) {
  if (typeof document === "undefined") return;

  const themedElements: HTMLElement[] = [document.documentElement, document.body].filter(
    (element): element is HTMLElement => Boolean(element),
  );

  if (preference === "system") {
    themedElements.forEach((element) => {
      element.removeAttribute("data-theme");
      element.style.colorScheme = "";
    });
    return;
  }

  themedElements.forEach((element) => {
    element.dataset.theme = preference;
    element.style.colorScheme = preference;
  });
}

function subscribeThemePreference(listener: () => void) {
  if (typeof window === "undefined") return () => undefined;
  const onStorage = (event: StorageEvent) => {
    if (event.key === themePreferenceKey) listener();
  };
  window.addEventListener("storage", onStorage);
  window.addEventListener(themePreferenceEvent, listener);
  return () => {
    window.removeEventListener("storage", onStorage);
    window.removeEventListener(themePreferenceEvent, listener);
  };
}

function subscribeSystemTheme(listener: () => void) {
  if (typeof window === "undefined") return () => undefined;
  const preferenceQuery = window.matchMedia("(prefers-color-scheme: dark)");
  preferenceQuery.addEventListener("change", listener);
  return () => preferenceQuery.removeEventListener("change", listener);
}

function getSystemTheme(): Exclude<ThemePreference, "system"> {
  if (typeof window === "undefined") return "light";
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function AuthenticatedThemeDefault() {
  useEffect(() => {
    applyThemePreference(getStoredThemePreference("dark"));
  }, []);

  return null;
}

export function ThemeToggle({ compact = false, defaultPreference = "system" }: ThemeToggleProps) {
  const themePreference = useSyncExternalStore(
    subscribeThemePreference,
    () => getStoredThemePreference(defaultPreference),
    () => defaultPreference,
  );
  const systemTheme = useSyncExternalStore(subscribeSystemTheme, getSystemTheme, () => "light" as const);

  useEffect(() => {
    applyThemePreference(themePreference);
  }, [themePreference]);

  useEffect(() => {
    if (themePreference !== "system") return;

    const preferenceQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const syncSystemTheme = () => applyThemePreference("system");
    syncSystemTheme();
    preferenceQuery.addEventListener("change", syncSystemTheme);
    return () => preferenceQuery.removeEventListener("change", syncSystemTheme);
  }, [themePreference]);

  const handleThemeChange = (preference: ThemePreference) => {
    try {
      window.localStorage.setItem(themePreferenceKey, preference);
    } catch {}
    applyThemePreference(preference);
    window.dispatchEvent(new Event(themePreferenceEvent));
  };

  if (compact) {
    const nextPreference = nextThemePreference(themePreference, systemTheme);
    const nextLabel = nextPreference === "dark" ? "oscuro" : "claro";

    return (
      <button
        aria-label={`Cambiar a modo ${nextLabel}`}
        className="theme-compact-toggle"
        onClick={() => handleThemeChange(nextPreference)}
        title={`Cambiar a modo ${nextLabel}`}
        type="button"
      >
        {nextPreference === "light" ? (
          <svg aria-hidden="true" fill="none" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2M12 20v2M4.93 4.93l1.42 1.42M17.65 17.65l1.42 1.42M2 12h2M20 12h2M4.93 19.07l1.42-1.42M17.65 6.35l1.42-1.42" />
          </svg>
        ) : (
          <svg aria-hidden="true" fill="none" viewBox="0 0 24 24">
            <path d="M20.2 15.1A8.5 8.5 0 0 1 8.9 3.8 8.5 8.5 0 1 0 20.2 15.1Z" />
          </svg>
        )}
      </button>
    );
  }

  return (
    <div className="theme-preference-panel">
      <span>Tema</span>
      <div className="theme-preference-options" role="group" aria-label="Tema de la web">
        {themePreferenceOptions.map((option) => (
          <button
            key={option.value}
            type="button"
            className={themePreference === option.value ? "active" : ""}
            aria-pressed={themePreference === option.value}
            onClick={() => handleThemeChange(option.value)}
          >
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}
