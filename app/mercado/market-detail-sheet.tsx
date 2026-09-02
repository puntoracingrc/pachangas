"use client";

import { useEffect, useRef, type KeyboardEvent, type ReactNode } from "react";
import styles from "./marketplace-v3d.module.css";

const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(",");

function focusableElements(container: HTMLElement) {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
    .filter((element) => !element.hidden && element.getAttribute("aria-hidden") !== "true");
}

function makeBackgroundInert(dialog: HTMLElement) {
  const changed: Array<{ ariaHidden: string | null; element: HTMLElement; inert: boolean }> = [];
  let branch: HTMLElement = dialog;
  let parent = branch.parentElement;

  while (parent) {
    for (const sibling of Array.from(parent.children)) {
      if (sibling === branch || !(sibling instanceof HTMLElement)) continue;
      changed.push({ ariaHidden: sibling.getAttribute("aria-hidden"), element: sibling, inert: sibling.inert });
      sibling.inert = true;
      sibling.setAttribute("aria-hidden", "true");
    }
    if (parent === document.body) break;
    branch = parent;
    parent = branch.parentElement;
  }

  return () => {
    for (const item of changed) {
      item.element.inert = item.inert;
      if (item.ariaHidden === null) item.element.removeAttribute("aria-hidden");
      else item.element.setAttribute("aria-hidden", item.ariaHidden);
    }
  };
}

export function MarketDetailSheet({
  children,
  label,
  onClose,
}: {
  children: ReactNode;
  label: string;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const previousOverflow = document.body.style.overflow;
    const restoreBackground = makeBackgroundInert(dialog);
    document.body.style.overflow = "hidden";
    closeRef.current?.focus({ preventScroll: true });

    return () => {
      restoreBackground();
      document.body.style.overflow = previousOverflow;
      if (opener?.isConnected) opener.focus({ preventScroll: true });
    };
  }, []);

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      onClose();
      return;
    }
    if (event.key !== "Tab" || !dialogRef.current) return;
    const focusable = focusableElements(dialogRef.current);
    if (!focusable.length) {
      event.preventDefault();
      dialogRef.current.focus({ preventScroll: true });
      return;
    }
    const first = focusable[0];
    const last = focusable.at(-1)!;
    if (event.shiftKey && (document.activeElement === first || !dialogRef.current.contains(document.activeElement))) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <div ref={dialogRef} className={styles.detailSheet} role="dialog" aria-modal="true" aria-label={label} onKeyDown={handleKeyDown} tabIndex={-1}>
      <button ref={closeRef} className={styles.detailClose} type="button" onClick={onClose} aria-label={`Cerrar ${label}`}>×</button>
      {children}
    </div>
  );
}
