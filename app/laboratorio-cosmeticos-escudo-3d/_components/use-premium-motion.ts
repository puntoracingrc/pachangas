"use client";

import { useCallback, useEffect, useState, type PointerEvent as ReactPointerEvent } from "react";

export type PremiumTilt = { x: number; y: number };
export type PremiumMotionSource = "pointer" | "reduced" | "sensor" | "simulation" | "static";
export type SensorPermission = "denied" | "granted" | "prompt" | "unavailable";

type DeviceOrientationConstructor = typeof DeviceOrientationEvent & {
  requestPermission?: () => Promise<"denied" | "granted">;
};

const STATIC_TILT: PremiumTilt = { x: 0, y: 0 };

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

export function usePremiumMotion({ enabled, reduced }: { enabled: boolean; reduced: boolean }) {
  const [sensorPermission, setSensorPermission] = useState<SensorPermission>("prompt");
  const [source, setSource] = useState<PremiumMotionSource>(reduced ? "reduced" : "static");
  const [tilt, setTilt] = useState<PremiumTilt>(STATIC_TILT);

  useEffect(() => {
    if (!enabled || reduced || sensorPermission !== "granted") return;
    const updateFromSensor = (event: DeviceOrientationEvent) => {
      const beta = event.beta ?? 0;
      const gamma = event.gamma ?? 0;
      setTilt({ x: clamp((beta - 45) / 5, -6, 6), y: clamp(gamma / 6, -6, 6) });
      setSource("sensor");
    };
    window.addEventListener("deviceorientation", updateFromSensor, { passive: true });
    return () => window.removeEventListener("deviceorientation", updateFromSensor);
  }, [enabled, reduced, sensorPermission]);

  const requestSensor = useCallback(async () => {
    if (!("DeviceOrientationEvent" in window)) {
      setSensorPermission("unavailable");
      return false;
    }
    try {
      const constructor = DeviceOrientationEvent as DeviceOrientationConstructor;
      const permission = constructor.requestPermission ? await constructor.requestPermission() : "granted";
      setSensorPermission(permission);
      if (permission !== "granted") {
        setTilt(STATIC_TILT);
        setSource("static");
        return false;
      }
      setSource("sensor");
      return true;
    } catch {
      setSensorPermission("denied");
      setTilt(STATIC_TILT);
      setSource("static");
      return false;
    }
  }, []);

  const handlePointerMove = useCallback((event: ReactPointerEvent<HTMLElement>) => {
    if (!enabled || reduced || sensorPermission === "granted" || event.pointerType === "touch") return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const horizontal = ((event.clientX - bounds.left) / bounds.width - 0.5) * 2;
    const vertical = ((event.clientY - bounds.top) / bounds.height - 0.5) * 2;
    setTilt({ x: clamp(-vertical * 5, -5, 5), y: clamp(horizontal * 6, -6, 6) });
    setSource("pointer");
  }, [enabled, reduced, sensorPermission]);

  const resetPointer = useCallback(() => {
    if (source !== "pointer") return;
    setTilt(STATIC_TILT);
    setSource("static");
  }, [source]);

  const simulateTilt = useCallback((next: PremiumTilt) => {
    if (!enabled || reduced) return;
    setTilt({ x: clamp(next.x, -6, 6), y: clamp(next.y, -6, 6) });
    setSource("simulation");
  }, [enabled, reduced]);

  return {
    handlePointerMove,
    requestSensor,
    resetPointer,
    sensorPermission,
    simulateTilt,
    source: reduced ? "reduced" : enabled ? source : "static",
    tilt: enabled && !reduced ? tilt : STATIC_TILT,
  };
}
