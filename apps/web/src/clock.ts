const JERUSALEM = "Asia/Jerusalem";

export function jerusalemParts(date = new Date()) {
  const bag: Record<string, string> = {};
  for (const part of new Intl.DateTimeFormat("en-US", {
    timeZone: JERUSALEM,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(date)) {
    if (part.type !== "literal") bag[part.type] = part.value;
  }
  return {
    year: Number(bag.year),
    month: Number(bag.month),
    day: Number(bag.day),
    hour: Number(bag.hour === "24" ? "0" : bag.hour),
    minute: Number(bag.minute),
    second: Number(bag.second),
  };
}

function locale() {
  return document.documentElement.lang === "he" ? "he-IL" : "en-GB";
}

export function formatJerusalem(iso: string): string {
  return new Intl.DateTimeFormat(locale(), {
    timeZone: JERUSALEM,
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(iso));
}

export function formatJerusalemDay(iso: string): string {
  return new Intl.DateTimeFormat(locale(), {
    timeZone: JERUSALEM,
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(iso));
}

export function formatJerusalemTime(iso: string): string {
  return new Intl.DateTimeFormat(locale(), {
    timeZone: JERUSALEM,
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso));
}

export function hourLabel(hour: number): string {
  return `${String(hour).padStart(2, "0")}:00`;
}

export function msUntilHour(hour: number, now = new Date()): number {
  const parts = jerusalemParts(now);
  const targetMinutes = hour * 60;
  const nowMinutes = parts.hour * 60 + parts.minute;
  const seconds = parts.second;
  let deltaMinutes = targetMinutes - nowMinutes;
  if (deltaMinutes < 0 || (deltaMinutes === 0 && seconds > 0)) deltaMinutes += 24 * 60;
  return deltaMinutes * 60 * 1000 - seconds * 1000;
}

export function addDays(day: string, count: number): string {
  const date = new Date(`${day}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
