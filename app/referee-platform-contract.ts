export const refereeModalities = ["FOOTBALL_11", "FOOTBALL_7", "FOOTBALL_5", "FUTSAL", "OTHER"] as const;
export const refereeAvailabilityStatuses = ["AVAILABLE", "LIMITED", "UNAVAILABLE"] as const;

export type RefereeModality = (typeof refereeModalities)[number];
export type RefereeAvailabilityStatus = (typeof refereeAvailabilityStatuses)[number];
export type RefereeJson = Record<string, unknown>;

export const refereeModalityLabels: Record<RefereeModality, string> = {
  FOOTBALL_11: "Fútbol 11",
  FOOTBALL_7: "Fútbol 7",
  FOOTBALL_5: "Fútbol 5",
  FUTSAL: "Fútbol sala",
  OTHER: "Otra modalidad",
};

export const refereeAvailabilityLabels: Record<RefereeAvailabilityStatus, string> = {
  AVAILABLE: "Disponible",
  LIMITED: "Disponibilidad limitada",
  UNAVAILABLE: "No disponible",
};

export const refereeWeekdayLabels = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"] as const;

export function refereeRecord(value: unknown): RefereeJson {
  return value && typeof value === "object" && !Array.isArray(value) ? value as RefereeJson : {};
}

export function refereeArray(value: unknown): RefereeJson[] {
  return Array.isArray(value) ? value.map(refereeRecord) : [];
}

export function refereeText(value: unknown) {
  if (typeof value === "string") return value;
  return typeof value === "number" && Number.isFinite(value) ? String(value) : "";
}

export function refereeNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function refereeBoolean(value: unknown) {
  return value === true;
}

export function refereeModalityLabel(value: unknown) {
  const modality = refereeText(value) as RefereeModality;
  return refereeModalityLabels[modality] ?? refereeText(value).replaceAll("_", " ");
}

export function refereeAvailabilityLabel(value: unknown) {
  const status = refereeText(value) as RefereeAvailabilityStatus;
  return refereeAvailabilityLabels[status] ?? "Sin disponibilidad publicada";
}

export function refereeDateLabel(value: unknown) {
  if (typeof value !== "string" || !value) return "Sin fecha";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Sin fecha";
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(date);
}

export function refereeStatusTone(value: unknown): "danger" | "good" | "info" | "muted" | "warning" {
  const status = refereeText(value).toLowerCase();
  if (/rejected|cancelled|revoked|suspended|archived/.test(status)) return "danger";
  if (/active|accepted|confirmed|completed|verified|listed/.test(status)) return "good";
  if (/pending|limited|proposed|requested|invited/.test(status)) return "warning";
  if (/available|draft|unverified/.test(status)) return "info";
  return "muted";
}
