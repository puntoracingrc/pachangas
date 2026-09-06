"use client";

import { useEffect, useState } from "react";

export function useAnimatedPoints(target: number, paused: boolean) {
  const [displayed, setDisplayed] = useState(target);
  useEffect(() => {
    if (paused) return;
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const timer = window.setInterval(() => {
      setDisplayed(previous => {
        const next = reduced ? target : previous + Math.sign(target - previous);
        if (next === target) window.clearInterval(timer);
        return next;
      });
    }, 40);
    return () => window.clearInterval(timer);
  }, [target, paused]);
  return displayed;
}
