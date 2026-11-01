export const JERUSALEM = "Asia/Jerusalem";

export type DayParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

const partFormat = new Intl.DateTimeFormat("en-US", {
  timeZone: JERUSALEM,
  hourCycle: "h23",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

export function jerusalemParts(date: Date): DayParts {
  const bag: Record<string, string> = {};
  for (const part of partFormat.formatToParts(date)) {
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

export function formatDay(parts: Pick<DayParts, "year" | "month" | "day">): string {
  const month = String(parts.month).padStart(2, "0");
  const day = String(parts.day).padStart(2, "0");
  return `${parts.year}-${month}-${day}`;
}

export function jerusalemDay(date: Date): string {
  return formatDay(jerusalemParts(date));
}

export function todayJerusalem(now = new Date()): string {
  return jerusalemDay(now);
}

export function isDayString(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const probe = new Date(Date.UTC(year, month - 1, day));
  return (
    probe.getUTCFullYear() === year &&
    probe.getUTCMonth() === month - 1 &&
    probe.getUTCDate() === day
  );
}

/** Year-first dates with `-`, `/`, or `.` separators, normalized to `yyyy-mm-dd`. */
export function canonicalDay(value: string): string | null {
  const match = value.trim().match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (!match) return null;
  const day = `${match[1]}-${match[2].padStart(2, "0")}-${match[3].padStart(2, "0")}`;
  return isDayString(day) ? day : null;
}

export function dayToUtcDate(day: string): Date {
  return new Date(`${day}T00:00:00.000Z`);
}

export function utcDateToDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function addDays(day: string, count: number): string {
  const date = dayToUtcDate(day);
  date.setUTCDate(date.getUTCDate() + count);
  return utcDateToDay(date);
}

export function compareDays(a: string, b: string): number {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

export function sundayOf(day: string): string {
  const date = dayToUtcDate(day);
  date.setUTCDate(date.getUTCDate() - date.getUTCDay());
  return utcDateToDay(date);
}

export function firstOfMonth(day: string): string {
  return `${day.slice(0, 8)}01`;
}

export function ageOn(dateOfBirth: string, on: string): number {
  const [y1, m1, d1] = dateOfBirth.split("-").map(Number);
  const [y2, m2, d2] = on.split("-").map(Number);
  let age = y2 - y1;
  if (m2 < m1 || (m2 === m1 && d2 < d1)) age -= 1;
  return age;
}

export function jerusalemMidnight(day: string): Date {
  return jerusalemWallTime(day, 0, 0, 0);
}

/** Instant when Asia/Jerusalem shows `day` at hour:minute:second. */
export function jerusalemWallTime(day: string, hour: number, minute = 0, second = 0): Date {
  let utc = new Date(`${day}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:${String(second).padStart(2, "0")}.000Z`);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const parts = jerusalemParts(utc);
    const seen = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
    const target = Date.UTC(
      Number(day.slice(0, 4)),
      Number(day.slice(5, 7)) - 1,
      Number(day.slice(8, 10)),
      hour,
      minute,
      second,
    );
    const next = new Date(utc.getTime() - (seen - target));
    if (next.getTime() === utc.getTime()) break;
    utc = next;
  }
  return utc;
}

export function weekBounds(sunday: string): { start: Date; end: Date } {
  return {
    start: jerusalemMidnight(sunday),
    end: jerusalemMidnight(addDays(sunday, 7)),
  };
}

export function daysOfWeek(sunday: string): string[] {
  return Array.from({ length: 7 }, (_, index) => addDays(sunday, index));
}
