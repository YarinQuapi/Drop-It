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

/** Today's date in Jerusalem as YYYY-MM-DD (the API's day boundary). */
export function todayJerusalemDay(now = new Date()): string {
  const { year, month, day } = jerusalemParts(now);
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function dayDate(day: string): Date {
  return new Date(`${day}T12:00:00.000Z`);
}

/** "2 – 8 Nov" style range for a Sunday-based week, localized. */
export function formatWeekRange(sunday: string): string {
  const format = new Intl.DateTimeFormat(locale(), { timeZone: "UTC", day: "numeric", month: "short" });
  return format.formatRange(dayDate(sunday), dayDate(addDays(sunday, 6)));
}

/** Short weekday ("Sun" / "א׳") for a YYYY-MM-DD day. */
export function formatWeekday(day: string): string {
  return new Intl.DateTimeFormat(locale(), { timeZone: "UTC", weekday: "short" }).format(dayDate(day));
}

/** "Sun, 8 Nov" style label for a YYYY-MM-DD day. */
export function formatDayLabel(day: string): string {
  return new Intl.DateTimeFormat(locale(), { timeZone: "UTC", weekday: "short", day: "numeric", month: "short" }).format(dayDate(day));
}
