export const ACTIVITY_MULTIPLIER = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  very: 1.725,
  extra: 1.9,
} as const;

export const PACE_DEFICIT = {
  kg025: 275,
  kg050: 550,
  kg100: 750,
} as const;

export type ActivityLevel = keyof typeof ACTIVITY_MULTIPLIER;
export type WeeklyPace = keyof typeof PACE_DEFICIT;
export type Sex = "male" | "female";
export type FoodBasis = "solid" | "liquid";

export type Nutrients = {
  calories: number;
  protein: number;
  carbohydrates: number;
  fat: number;
  fiber: number;
  sugars: number;
  sodium: number;
};

export function approximateEndHour(startHour: number, lengthHours: number): number {
  return (startHour + lengthHours) % 24;
}

export function fastEndsAt(startedAt: Date, lengthHours: number): Date {
  return new Date(startedAt.getTime() + lengthHours * 60 * 60 * 1000);
}

export function fastDurationMinutes(startedAt: Date, endedAt: Date): number {
  return Math.max(0, Math.round((endedAt.getTime() - startedAt.getTime()) / 60000));
}

export const REMINDER_OFFSETS = [0, 30, 60] as const;
export type ReminderOffset = (typeof REMINDER_OFFSETS)[number];
export type FastNotificationKind = "lead" | "late" | "done";

export type FastNotification = {
  id: string;
  at: string;
  kind: FastNotificationKind;
  leadMinutes: number | null;
};

const EARLY_START_MS = 4 * 60 * 60 * 1000;
const LATE_NUDGE_MS = 15 * 60 * 1000;
const ALLOWED_OFFSETS = new Set<number>(REMINDER_OFFSETS);

export function parseReminderOffsets(raw: string | null | undefined): ReminderOffset[] {
  if (raw == null || raw.trim() === "") return [];
  const seen = new Set<ReminderOffset>();
  for (const part of raw.split(",")) {
    const value = Number(part.trim());
    if (ALLOWED_OFFSETS.has(value)) seen.add(value as ReminderOffset);
  }
  return REMINDER_OFFSETS.filter((offset) => seen.has(offset));
}

export function serializeReminderOffsets(offsets: number[]): string {
  const seen = new Set<ReminderOffset>();
  for (const value of offsets) {
    if (ALLOWED_OFFSETS.has(value)) seen.add(value as ReminderOffset);
  }
  return REMINDER_OFFSETS.filter((offset) => seen.has(offset)).join(",");
}

/** True when a session start belongs to the scheduled window (early start allowed). */
export function sessionCoversScheduledStart(sessionStarts: Date[], scheduledStart: Date): boolean {
  const open = scheduledStart.getTime() - EARLY_START_MS;
  const close = scheduledStart.getTime() + LATE_NUDGE_MS;
  return sessionStarts.some((startedAt) => {
    const t = startedAt.getTime();
    return t >= open && t <= close;
  });
}

export function planFastNotifications(input: {
  enabled: boolean;
  startHour: number;
  reminderOffsets: ReminderOffset[];
  running: boolean;
  endsAt: Date | null;
  sessionStarts: Date[];
  now?: Date;
  days?: number;
  wallTime: (day: string, hour: number, minute?: number) => Date;
  today: (now?: Date) => string;
  addDays: (day: string, count: number) => string;
}): FastNotification[] {
  const now = input.now ?? new Date();
  const notifications: FastNotification[] = [];
  if (!input.enabled) {
    if (input.running && input.endsAt && input.endsAt.getTime() > now.getTime()) {
      notifications.push({
        id: "done",
        at: input.endsAt.toISOString(),
        kind: "done",
        leadMinutes: null,
      });
    }
    return notifications;
  }

  const dayCount = input.days ?? 7;
  const today = input.today(now);
  for (let offsetDay = 0; offsetDay < dayCount; offsetDay += 1) {
    const day = input.addDays(today, offsetDay);
    const scheduledStart = input.wallTime(day, input.startHour, 0);
    for (const lead of input.reminderOffsets) {
      const at = new Date(scheduledStart.getTime() - lead * 60 * 1000);
      if (at.getTime() <= now.getTime()) continue;
      notifications.push({
        id: `lead-${day}-${lead}`,
        at: at.toISOString(),
        kind: "lead",
        leadMinutes: lead,
      });
    }
    const lateAt = new Date(scheduledStart.getTime() + LATE_NUDGE_MS);
    const covered = sessionCoversScheduledStart(input.sessionStarts, scheduledStart);
    const stillFastingThroughLate =
      input.running && input.endsAt != null && lateAt.getTime() <= input.endsAt.getTime();
    if (lateAt.getTime() > now.getTime() && !covered && !stillFastingThroughLate) {
      notifications.push({
        id: `late-${day}`,
        at: lateAt.toISOString(),
        kind: "late",
        leadMinutes: null,
      });
    }
  }

  if (input.running && input.endsAt && input.endsAt.getTime() > now.getTime()) {
    notifications.push({
      id: "done",
      at: input.endsAt.toISOString(),
      kind: "done",
      leadMinutes: null,
    });
  }

  notifications.sort((a, b) => a.at.localeCompare(b.at) || a.id.localeCompare(b.id));
  return notifications;
}

export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function mifflinStJeor(input: { sex: Sex; weightKg: number; heightCm: number; age: number }): number {
  const base = 10 * input.weightKg + 6.25 * input.heightCm - 5 * input.age;
  return input.sex === "male" ? base + 5 : base - 161;
}

export function sexCalorieFloor(sex: Sex): number {
  return sex === "male" ? 1500 : 1200;
}

export function calorieSafetyFloor(input: { sex: Sex; weightKg: number; heightCm: number; age: number }): number {
  return Math.max(Math.round(mifflinStJeor(input)), sexCalorieFloor(input.sex));
}

export function suggestedCalorieGoal(input: {
  sex: Sex;
  weightKg: number;
  heightCm: number;
  age: number;
  activity: ActivityLevel;
  pace: WeeklyPace;
}): number {
  const resting = mifflinStJeor(input);
  const raw = resting * ACTIVITY_MULTIPLIER[input.activity] - PACE_DEFICIT[input.pace];
  return Math.round(Math.max(raw, calorieSafetyFloor(input)));
}

export function calorieGoal(input: {
  sex: Sex;
  weightKg: number;
  heightCm: number;
  age: number;
  activity: ActivityLevel;
  pace: WeeklyPace;
  customGoalKcal?: number | null;
}): number {
  const floor = calorieSafetyFloor(input);
  if (input.customGoalKcal != null) {
    return Math.round(Math.max(input.customGoalKcal, floor));
  }
  return suggestedCalorieGoal(input);
}

export function weightForGoal(input: {
  day: string;
  profileWeightKg: number;
  weighIns: { loggedAt: Date; weightKg: number }[];
  jerusalemDay: (date: Date) => string;
  firstOfMonth: (day: string) => string;
}): number {
  if (input.weighIns.length === 0) return input.profileWeightKg;
  const monthStart = input.firstOfMonth(input.day);
  const before = input.weighIns.filter((entry) => input.jerusalemDay(entry.loggedAt) < monthStart);
  if (before.length === 0) return input.profileWeightKg;
  before.sort((a, b) => b.loggedAt.getTime() - a.loggedAt.getTime());
  return before[0].weightKg;
}

export function scaleNutrients(per100: Nutrients, amount: number): Nutrients {
  const factor = amount / 100;
  return {
    calories: round2(per100.calories * factor),
    protein: round2(per100.protein * factor),
    carbohydrates: round2(per100.carbohydrates * factor),
    fat: round2(per100.fat * factor),
    fiber: round2(per100.fiber * factor),
    sugars: round2(per100.sugars * factor),
    sodium: round2(per100.sodium * factor),
  };
}

export function sumNutrients(rows: Nutrients[]): Nutrients {
  const total = {
    calories: 0,
    protein: 0,
    carbohydrates: 0,
    fat: 0,
    fiber: 0,
    sugars: 0,
    sodium: 0,
  };
  for (const row of rows) {
    total.calories += row.calories;
    total.protein += row.protein;
    total.carbohydrates += row.carbohydrates;
    total.fat += row.fat;
    total.fiber += row.fiber;
    total.sugars += row.sugars;
    total.sodium += row.sodium;
  }
  return {
    calories: round2(total.calories),
    protein: round2(total.protein),
    carbohydrates: round2(total.carbohydrates),
    fat: round2(total.fat),
    fiber: round2(total.fiber),
    sugars: round2(total.sugars),
    sodium: round2(total.sodium),
  };
}

export type DayStatus = "future" | "empty" | "on_track" | "over" | "met";

type DayInput = { entryCount: number; calories: number; goalKcal: number; future: boolean; today?: boolean };

/**
 * "met" only once a day is over: today stays "on_track" while under the goal,
 * otherwise a breakfast-only day would already count as a success.
 */
export function dayStatus(input: DayInput): DayStatus {
  if (input.future) return "future";
  if (input.entryCount === 0) return "empty";
  if (input.calories > input.goalKcal) return "over";
  return input.today ? "on_track" : "met";
}

export function daySucceeded(input: DayInput): boolean {
  return dayStatus(input) === "met";
}

/**
 * A day uses the sedentary base only while Apple Health is connected, from the
 * connection day through today. Future days keep the profile estimate.
 * Active calories stay visible as activity and do not raise the food budget.
 */
export function usesHealthBase(input: {
  connected: boolean;
  connectedOn: string | null;
  day: string;
  today: string;
}): boolean {
  if (!input.connected || input.connectedOn == null) return false;
  return input.day >= input.connectedOn && input.day <= input.today;
}

/** Food budget for a day. Active calories are ignored so exercise does not add calories you can eat. */
export function effectiveGoalKcal(baseGoalKcal: number, _activeKcal: number, _healthAdjusted: boolean): number {
  return baseGoalKcal;
}

export type WeekDayCandidate = {
  day: string;
  goalKcal: number;
  calories: number;
  entryCount: number;
  success: boolean;
  status?: DayStatus;
  future: boolean;
  steps?: number | null;
  exerciseMinutes?: number | null;
  activeKcal?: number;
};

export type WeekDaySummary = Omit<WeekDayCandidate, "entryCount">;

export function summarizeWeekDays(rows: WeekDayCandidate[]): {
  goalKcal: number;
  activeKcal: number;
  calorieIntake: number;
  successCount: number;
  days: WeekDaySummary[];
} {
  const goalKcal = rows.reduce((sum, row) => sum + row.goalKcal, 0);
  const activeKcal = rows.reduce((sum, row) => sum + (row.activeKcal ?? 0), 0);
  const calorieIntake = round2(rows.reduce((sum, row) => sum + row.calories, 0));
  const successCount = rows.filter((row) => row.success).length;
  const days = rows
    .filter((row) => !row.future && row.entryCount > 0 && row.calories > 0)
    .map(({ entryCount: _entryCount, ...row }) => row);
  return { goalKcal, activeKcal, calorieIntake, successCount, days };
}

export type BarcodeStatus = "personal" | "verified" | "list" | "none";

export function resolveBarcode<T>(input: { own: T | null; verified: T | null; published: T[] }): {
  status: BarcodeStatus;
  food: T | null;
  foods: T[];
} {
  if (input.own) return { status: "personal", food: input.own, foods: [] };
  if (input.verified) return { status: "verified", food: input.verified, foods: [] };
  if (input.published.length > 0) return { status: "list", food: null, foods: input.published };
  return { status: "none", food: null, foods: [] };
}

export function weightChangeKg(input: {
  weights: { loggedAt: Date; weightKg: number }[];
  start: Date;
  end: Date;
}): number | null {
  const inWeek = input.weights.filter((entry) => entry.loggedAt >= input.start && entry.loggedAt < input.end);
  const before = input.weights.filter((entry) => entry.loggedAt < input.start);
  if (inWeek.length === 0 || before.length === 0) return null;
  inWeek.sort((a, b) => b.loggedAt.getTime() - a.loggedAt.getTime());
  before.sort((a, b) => b.loggedAt.getTime() - a.loggedAt.getTime());
  return round2(inWeek[0].weightKg - before[0].weightKg);
}

export type PasswordChecks = {
  length: boolean;
  english: boolean;
  uppercase: boolean;
  number: boolean;
  symbol: boolean;
  match: boolean;
  valid: boolean;
};

export function checkPassword(password: string, confirmPassword: string = password): PasswordChecks {
  const length = password.length >= 8 && password.length <= 200;
  const english = password.length > 0 && /^[\x21-\x7E]+$/.test(password);
  const uppercase = /[A-Z]/.test(password);
  const number = /[0-9]/.test(password);
  const symbol = /[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/.test(password);
  const match = password.length > 0 && password === confirmPassword;
  return {
    length,
    english,
    uppercase,
    number,
    symbol,
    match,
    valid: length && english && uppercase && number && symbol && match,
  };
}

export function validatePassword(password: string, confirmPassword?: string): "ok" | "weak_password" | "password_mismatch" {
  const checks = checkPassword(password, confirmPassword ?? password);
  if (!checks.length || !checks.english || !checks.uppercase || !checks.number || !checks.symbol) {
    return "weak_password";
  }
  if (confirmPassword !== undefined && !checks.match) {
    return "password_mismatch";
  }
  return "ok";
}

