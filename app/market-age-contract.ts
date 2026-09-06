export function madridToday() {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Madrid", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

export function validBirthDate(value: unknown, today = madridToday()): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value
    && value <= today && Number(value.slice(0, 4)) >= Number(today.slice(0, 4)) - 120;
}

export function isAdultBirthDate(value: unknown, today = madridToday()) {
  if (!validBirthDate(value, today)) return false;
  return value <= `${Number(today.slice(0, 4)) - 18}${today.slice(4)}`;
}

export type MarketAgeAccess = "adult" | "minor" | "missing";
