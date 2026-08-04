"use client";

import { useCallback, useSyncExternalStore } from "react";

const adminViewPreviewStorageKey = "pachangas-admin-view-preview";
const adminViewPreviewEvent = "pachangas-admin-view-preview-change";

function adminViewPreviewSnapshot() {
  return window.sessionStorage.getItem(adminViewPreviewStorageKey) === "player";
}

function subscribeToAdminViewPreview(listener: () => void) {
  window.addEventListener(adminViewPreviewEvent, listener);
  return () => window.removeEventListener(adminViewPreviewEvent, listener);
}

export function useAdminViewPreview() {
  const previewRequested = useSyncExternalStore(subscribeToAdminViewPreview, adminViewPreviewSnapshot, () => false);

  const toggleAdminViewPreview = useCallback(() => {
    if (adminViewPreviewSnapshot()) {
      window.sessionStorage.removeItem(adminViewPreviewStorageKey);
    } else {
      window.sessionStorage.setItem(adminViewPreviewStorageKey, "player");
    }
    window.dispatchEvent(new Event(adminViewPreviewEvent));
  }, []);

  return { previewRequested, toggleAdminViewPreview };
}
