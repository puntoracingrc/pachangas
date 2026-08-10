"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { TEAM_SHIELD_PREMIUM_BALL_FRAMES } from "../team-shield-premium-assets";
import {
  advancePremiumOrientationPipeline,
  INITIAL_PREMIUM_ORIENTATION_STATE,
  normalizePremiumScreenAngle,
  resolvePremiumMotionStatus,
  resetPremiumOrientationCalibration,
  STATIC_PREMIUM_BALL_VISUAL,
  type PremiumBallVisualState,
  type PremiumOrientationPipelineState,
  type PremiumMotionStatus,
} from "../team-shield-premium-motion";

type DeviceOrientationPermission = "denied" | "granted";
type DeviceOrientationConstructor = typeof DeviceOrientationEvent & {
  requestPermission?: () => Promise<DeviceOrientationPermission>;
};

export type TeamShieldPremiumMotionStatus = PremiumMotionStatus;

function currentScreenAngle() {
  const orientationAngle = window.screen.orientation?.angle;
  const legacyAngle = "orientation" in window ? Number(window.orientation) : 0;
  return normalizePremiumScreenAngle(Number.isFinite(orientationAngle) ? orientationAngle : legacyAngle);
}

export function useTeamShieldPremiumMotion() {
  const [enabled, setEnabled] = useState(false);
  const [permission, setPermission] = useState<"denied" | "granted" | "prompt" | "unavailable">("prompt");
  const [reduced, setReduced] = useState(() => (
    typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
  ));
  const [documentVisible, setDocumentVisible] = useState(() => (
    typeof document === "undefined" || document.visibilityState !== "hidden"
  ));
  const [inViewport, setInViewport] = useState(true);
  const [viewportNode, setViewportNode] = useState<HTMLDivElement | null>(null);
  const [visual, setVisual] = useState<PremiumBallVisualState>(STATIC_PREMIUM_BALL_VISUAL);
  const pipelineRef = useRef<PremiumOrientationPipelineState>(INITIAL_PREMIUM_ORIENTATION_STATE);
  const lastSensorUpdateRef = useRef(0);

  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => {
      setReduced(query.matches);
      if (query.matches) {
        pipelineRef.current = resetPremiumOrientationCalibration();
        setVisual(STATIC_PREMIUM_BALL_VISUAL);
      }
    };
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    const update = () => {
      const visible = document.visibilityState !== "hidden";
      setDocumentVisible(visible);
      if (visible) {
        lastSensorUpdateRef.current = 0;
        pipelineRef.current = resetPremiumOrientationCalibration();
        setVisual(STATIC_PREMIUM_BALL_VISUAL);
      }
    };
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);

  useEffect(() => {
    const target = viewportNode;
    if (!target || !("IntersectionObserver" in window)) return;
    const observer = new IntersectionObserver(([entry]) => {
      const visible = entry?.isIntersecting ?? true;
      if (visible) {
        lastSensorUpdateRef.current = 0;
        pipelineRef.current = resetPremiumOrientationCalibration();
        setVisual(STATIC_PREMIUM_BALL_VISUAL);
      }
      setInViewport(visible);
    }, { rootMargin: "80px", threshold: 0.01 });
    observer.observe(target);
    return () => observer.disconnect();
  }, [viewportNode]);

  useEffect(() => {
    if (!enabled || reduced || permission !== "granted" || !documentVisible || !inViewport) return;

    const updateFromSensor = (event: DeviceOrientationEvent) => {
      if (lastSensorUpdateRef.current > 0 && event.timeStamp - lastSensorUpdateRef.current < 16) return;
      lastSensorUpdateRef.current = event.timeStamp;
      const next = advancePremiumOrientationPipeline(pipelineRef.current, event, currentScreenAngle());
      if (next === pipelineRef.current) return;
      pipelineRef.current = next;
      setVisual(next.visual);
    };
    const recalibrate = () => {
      lastSensorUpdateRef.current = 0;
      pipelineRef.current = resetPremiumOrientationCalibration();
      setVisual(STATIC_PREMIUM_BALL_VISUAL);
    };
    const orientation = window.screen.orientation;
    window.addEventListener("deviceorientation", updateFromSensor, { passive: true });
    window.addEventListener("orientationchange", recalibrate);
    orientation?.addEventListener("change", recalibrate);
    return () => {
      window.removeEventListener("deviceorientation", updateFromSensor);
      window.removeEventListener("orientationchange", recalibrate);
      orientation?.removeEventListener("change", recalibrate);
    };
  }, [documentVisible, enabled, inViewport, permission, reduced]);

  useEffect(() => {
    if (!enabled || reduced || !inViewport) return;
    const preloads = TEAM_SHIELD_PREMIUM_BALL_FRAMES.map((source) => {
      const image = new window.Image();
      image.decoding = "async";
      image.src = source;
      return image;
    });
    return () => preloads.forEach((image) => { image.src = ""; });
  }, [enabled, inViewport, reduced]);

  const activate = useCallback(async () => {
    if (reduced || permission === "denied" || permission === "unavailable") return false;
    if (!("DeviceOrientationEvent" in window)) {
      setPermission("unavailable");
      setEnabled(false);
      return false;
    }
    try {
      const constructor = window.DeviceOrientationEvent as DeviceOrientationConstructor;
      const result = constructor.requestPermission ? await constructor.requestPermission() : "granted";
      if (result !== "granted") {
        setPermission("denied");
        setEnabled(false);
        setVisual(STATIC_PREMIUM_BALL_VISUAL);
        return false;
      }
      pipelineRef.current = resetPremiumOrientationCalibration();
      lastSensorUpdateRef.current = 0;
      setVisual(STATIC_PREMIUM_BALL_VISUAL);
      setPermission("granted");
      setEnabled(true);
      return true;
    } catch {
      setPermission("denied");
      setEnabled(false);
      setVisual(STATIC_PREMIUM_BALL_VISUAL);
      return false;
    }
  }, [permission, reduced]);

  const deactivate = useCallback(() => {
    setEnabled(false);
    pipelineRef.current = resetPremiumOrientationCalibration();
    lastSensorUpdateRef.current = 0;
    setVisual(STATIC_PREMIUM_BALL_VISUAL);
  }, []);

  const status = resolvePremiumMotionStatus({ enabled, permission, reduced });

  return {
    activate,
    deactivate,
    setViewportNode,
    status,
    visual: status === "active" ? visual : STATIC_PREMIUM_BALL_VISUAL,
  };
}
