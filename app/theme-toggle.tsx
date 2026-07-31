"use client";

import { useEffect, useState } from "react";

type ThemePreference = "system" | "light" | "dark";

const themePreferenceKey = "pachanga-iq-theme";
const themePreferenceOptions: Array<{ value: ThemePreference; label: string }> = [
  { value: "system", label: "Sistema" },
  { value: "light", label: "Claro" },
  { value: "dark", label: "Oscuro" },
];

function normalizeThemePreference(value: string | null): ThemePreference {
  return value === "light" || value === "dark" ? value : "system";
}

function getStoredThemePreference(): ThemePreference {
  if (typeof window === "undefined") return "system";

  try {
    return normalizeThemePreference(window.localStorage.getItem(themePreferenceKey));
  } catch {
    return "system";
  }
}

function applyThemePreference(preference: ThemePreference) {
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

export function ThemeToggle() {
  const [themePreference, setThemePreference] = useState<ThemePreference>("system");
  const [isMounted, setIsMounted] = useState(false);

  useEffect(() => {
    const storedPreference = getStoredThemePreference();
    setThemePreference(storedPreference);
    applyThemePreference(storedPreference);
    setIsMounted(true);
  }, []);

  useEffect(() => {
    if (!isMounted) return;

    try {
      window.localStorage.setItem(themePreferenceKey, themePreference);
    } catch {}
    applyThemePreference(themePreference);
  }, [isMounted, themePreference]);

  useEffect(() => {
    if (themePreference !== "system") return;

    const preferenceQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const syncSystemTheme = () => applyThemePreference("system");
    syncSystemTheme();
    preferenceQuery.addEventListener("change", syncSystemTheme);
    return () => preferenceQuery.removeEventListener("change", syncSystemTheme);
  }, [themePreference]);

  const handleThemeChange = (preference: ThemePreference) => {
    setThemePreference(preference);
    applyThemePreference(preference);
  };

  return (
    <div className="theme-preference-panel">
      <span>Tema</span>
      <div className="theme-preference-options" role="group" aria-label="Tema de la web">
        {themePreferenceOptions.map((option) => (
          <button
            key={option.value}
            type="button"
            className={isMounted && themePreference === option.value ? "active" : ""}
            aria-pressed={isMounted && themePreference === option.value}
            onClick={() => handleThemeChange(option.value)}
          >
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}
