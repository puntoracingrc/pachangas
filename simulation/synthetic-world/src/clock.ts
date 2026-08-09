const DAY_MS = 86_400_000;

export function startOfVirtualDay(value: string | Date) {
  const date = typeof value === "string" ? new Date(value) : value;
  if (!Number.isFinite(date.getTime())) throw new Error(`Invalid virtual date: ${String(value)}`);
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

export function addVirtualDays(value: string | Date, days: number) {
  return new Date(startOfVirtualDay(value).getTime() + days * DAY_MS);
}

export function virtualDay(value: string | Date) {
  return startOfVirtualDay(value).toISOString();
}

export function virtualDaysBetween(left: string | Date, right: string | Date) {
  return Math.floor((startOfVirtualDay(right).getTime() - startOfVirtualDay(left).getTime()) / DAY_MS);
}

export function virtualWeek(start: string, value: string | Date) {
  return Math.max(1, Math.floor(virtualDaysBetween(start, value) / 7) + 1);
}

export function eachVirtualDayExclusive(start: string, end: string) {
  const days = virtualDaysBetween(start, end);
  if (days < 0) throw new Error("The synthetic clock cannot run backwards; clone an earlier snapshot instead.");
  return Array.from({ length: days }, (_, index) => addVirtualDays(start, index + 1));
}

export function atVirtualHour(value: string | Date, hour: number, minute = 0) {
  const date = startOfVirtualDay(value);
  date.setUTCHours(hour, minute, 0, 0);
  return date.toISOString();
}
