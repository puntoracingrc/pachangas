export type AdaptiveWidthClass = "compact" | "medium" | "expanded" | "large" | "extra-large";
export type AdaptiveHeightClass = "compact" | "medium" | "expanded";

export type AdaptiveWindowClass = {
  height: AdaptiveHeightClass;
  width: AdaptiveWidthClass;
};

export function adaptiveWidthClass(width: number): AdaptiveWidthClass {
  if (width >= 1600) return "extra-large";
  if (width >= 1200) return "large";
  if (width >= 840) return "expanded";
  if (width >= 600) return "medium";
  return "compact";
}

export function adaptiveHeightClass(height: number): AdaptiveHeightClass {
  if (height >= 900) return "expanded";
  if (height >= 480) return "medium";
  return "compact";
}

export function adaptiveWindowClass(width: number, height: number): AdaptiveWindowClass {
  return {
    height: adaptiveHeightClass(height),
    width: adaptiveWidthClass(width),
  };
}
