export const TEAM_SHIELD_PREMIUM_FRAME_COUNT = 8;
export const TEAM_SHIELD_PREMIUM_MAX_TILT = 6;
export const TEAM_SHIELD_PREMIUM_DEAD_ZONE = 1.15;
export const TEAM_SHIELD_PREMIUM_SMOOTHING = 0.18;
export const TEAM_SHIELD_PREMIUM_FRAME_HYSTERESIS = 0.28;

export type PremiumOrientationSample = {
  alpha?: number | null;
  beta?: number | null;
  gamma?: number | null;
};

export type PremiumMappedOrientation = { x: number; y: number };
export type PremiumScreenAngle = 0 | 90 | 180 | 270;

export type PremiumBallVisualState = {
  blend: number;
  frame: number;
  previousFrame: number;
  tiltX: number;
  tiltY: number;
};

export type PremiumOrientationPipelineState = {
  neutral: PremiumMappedOrientation | null;
  visual: PremiumBallVisualState;
};

export type PremiumMotionPermission = "denied" | "granted" | "prompt" | "unavailable";
export type PremiumMotionStatus = "active" | "denied" | "off" | "reduced" | "unavailable";

export const STATIC_PREMIUM_BALL_VISUAL: PremiumBallVisualState = {
  blend: 1,
  frame: 4,
  previousFrame: 4,
  tiltX: 0,
  tiltY: 0,
};

export const INITIAL_PREMIUM_ORIENTATION_STATE: PremiumOrientationPipelineState = {
  neutral: null,
  visual: STATIC_PREMIUM_BALL_VISUAL,
};

export function clampPremiumValue(value: number, min: number, max: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.min(max, Math.max(min, value));
}

export function normalizePremiumScreenAngle(value: number | null | undefined): PremiumScreenAngle {
  if (!Number.isFinite(value)) return 0;
  const normalized = ((Math.round(Number(value) / 90) * 90) % 360 + 360) % 360;
  if (normalized === 90 || normalized === 180 || normalized === 270) return normalized;
  return 0;
}

export function mapPremiumOrientationToViewport(
  sample: PremiumOrientationSample,
  screenAngle: PremiumScreenAngle,
): PremiumMappedOrientation | null {
  if (!Number.isFinite(sample.beta) || !Number.isFinite(sample.gamma)) return null;
  const beta = clampPremiumValue(Number(sample.beta), -180, 180);
  const gamma = clampPremiumValue(Number(sample.gamma), -90, 90);
  if (screenAngle === 90) return { x: beta, y: -gamma };
  if (screenAngle === 180) return { x: -gamma, y: -beta };
  if (screenAngle === 270) return { x: -beta, y: gamma };
  return { x: gamma, y: beta };
}

export function applyPremiumDeadZone(value: number, deadZone = TEAM_SHIELD_PREMIUM_DEAD_ZONE) {
  const magnitude = Math.abs(value);
  if (magnitude <= deadZone) return 0;
  return Math.sign(value) * (magnitude - deadZone);
}

export function smoothPremiumValue(previous: number, target: number, smoothing = TEAM_SHIELD_PREMIUM_SMOOTHING) {
  const safeSmoothing = clampPremiumValue(smoothing, 0, 1);
  return previous + (target - previous) * safeSmoothing;
}

function frameCenter(frame: number) {
  return (clampPremiumValue(frame, 0, TEAM_SHIELD_PREMIUM_FRAME_COUNT - 1) / (TEAM_SHIELD_PREMIUM_FRAME_COUNT - 1))
    * TEAM_SHIELD_PREMIUM_MAX_TILT * 2 - TEAM_SHIELD_PREMIUM_MAX_TILT;
}

export function selectPremiumBallFrame(
  tilt: number,
  previousFrame: number,
  hysteresis = TEAM_SHIELD_PREMIUM_FRAME_HYSTERESIS,
) {
  const clampedTilt = clampPremiumValue(tilt, -TEAM_SHIELD_PREMIUM_MAX_TILT, TEAM_SHIELD_PREMIUM_MAX_TILT);
  const exact = ((clampedTilt + TEAM_SHIELD_PREMIUM_MAX_TILT) / (TEAM_SHIELD_PREMIUM_MAX_TILT * 2))
    * (TEAM_SHIELD_PREMIUM_FRAME_COUNT - 1);
  const candidate = Math.round(exact);
  const previous = Math.round(clampPremiumValue(previousFrame, 0, TEAM_SHIELD_PREMIUM_FRAME_COUNT - 1));
  if (candidate === previous) return previous;
  const frameStep = (TEAM_SHIELD_PREMIUM_MAX_TILT * 2) / (TEAM_SHIELD_PREMIUM_FRAME_COUNT - 1);
  const threshold = frameStep / 2 + Math.max(0, hysteresis);
  return Math.abs(clampedTilt - frameCenter(previous)) >= threshold ? candidate : previous;
}

export function advancePremiumOrientationPipeline(
  previous: PremiumOrientationPipelineState,
  sample: PremiumOrientationSample,
  screenAngle: PremiumScreenAngle,
): PremiumOrientationPipelineState {
  const mapped = mapPremiumOrientationToViewport(sample, screenAngle);
  if (!mapped) return previous;
  if (!previous.neutral) return { neutral: mapped, visual: STATIC_PREMIUM_BALL_VISUAL };

  const horizontalDelta = applyPremiumDeadZone(mapped.x - previous.neutral.x);
  const verticalDelta = applyPremiumDeadZone(mapped.y - previous.neutral.y);
  const targetX = clampPremiumValue(horizontalDelta / 2.25, -TEAM_SHIELD_PREMIUM_MAX_TILT, TEAM_SHIELD_PREMIUM_MAX_TILT);
  const targetY = clampPremiumValue(verticalDelta / 2.25, -TEAM_SHIELD_PREMIUM_MAX_TILT, TEAM_SHIELD_PREMIUM_MAX_TILT);
  const tiltX = smoothPremiumValue(previous.visual.tiltX, targetX);
  const tiltY = smoothPremiumValue(previous.visual.tiltY, targetY);
  const frame = selectPremiumBallFrame(tiltX, previous.visual.frame);
  const changedFrame = frame !== previous.visual.frame;
  const blend = changedFrame ? 0.18 : Math.min(1, previous.visual.blend + 0.22);

  if (
    tiltX === previous.visual.tiltX
    && tiltY === previous.visual.tiltY
    && frame === previous.visual.frame
    && blend === previous.visual.blend
  ) return previous;

  return {
    neutral: previous.neutral,
    visual: {
      blend,
      frame,
      previousFrame: changedFrame ? previous.visual.frame : previous.visual.previousFrame,
      tiltX,
      tiltY,
    },
  };
}

export function resetPremiumOrientationCalibration(
  visual: PremiumBallVisualState = STATIC_PREMIUM_BALL_VISUAL,
): PremiumOrientationPipelineState {
  return { neutral: null, visual: { ...visual, blend: 1, tiltX: 0, tiltY: 0 } };
}

export function resolvePremiumMotionStatus({
  enabled,
  permission,
  reduced,
}: {
  enabled: boolean;
  permission: PremiumMotionPermission;
  reduced: boolean;
}): PremiumMotionStatus {
  if (reduced) return "reduced";
  if (permission === "denied") return "denied";
  if (permission === "unavailable") return "unavailable";
  return enabled ? "active" : "off";
}
