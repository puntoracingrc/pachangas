export type PlayerCardOnboardingStatus = "checking" | "complete" | "error" | "not-required" | "required";

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

export function hasCanonicalInitialAssessment(snapshot: unknown) {
  if (!isRecord(snapshot) || !isRecord(snapshot.assessments)) return false;
  const initial = snapshot.assessments.initial;
  return Boolean(
    isRecord(initial)
      && typeof initial.completedAt === "string"
      && initial.completedAt.trim(),
  );
}
