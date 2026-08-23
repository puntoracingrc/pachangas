"use client";

import { useEffect, useSyncExternalStore } from "react";

export type ThemePreference = "system" | "light" | "dark";

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

export function AuthenticatedThemeDefault() {
  useEffect(() => {
    applyThemePreference(getStoredThemePreference("dark"));
  }, []);

  return null;
}

export function ThemeToggle({ defaultPreference = "system" }: { defaultPreference?: ThemePreference }) {
  const themePreference = useSyncExternalStore(
    subscribeThemePreference,
    () => getStoredThemePreference(defaultPreference),
    () => defaultPreference,
  );

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
