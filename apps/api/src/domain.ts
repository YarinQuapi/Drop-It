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
  kg100: 1100,
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

export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function mifflinStJeor(input: { sex: Sex; weightKg: number; heightCm: number; age: number }): number {
  const base = 10 * input.weightKg + 6.25 * input.heightCm - 5 * input.age;
  return input.sex === "male" ? base + 5 : base - 161;
}

export function calorieGoal(input: {
  sex: Sex;
  weightKg: number;
  heightCm: number;
  age: number;
  activity: ActivityLevel;
  pace: WeeklyPace;
}): number {
  const resting = mifflinStJeor(input);
  let raw = resting * ACTIVITY_MULTIPLIER[input.activity] - PACE_DEFICIT[input.pace];
  if (raw < 800) raw = 800;
  return Math.round(raw);
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

export function daySucceeded(input: { entryCount: number; calories: number; goalKcal: number; future: boolean }): boolean {
  if (input.future || input.entryCount === 0) return false;
  return input.calories <= input.goalKcal;
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

