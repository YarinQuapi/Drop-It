export type ActivityLevel = "sedentary" | "light" | "moderate" | "very" | "extra";
export type WeeklyPace = "kg025" | "kg050" | "kg100";
export type Sex = "male" | "female";

const ACTIVITY_MULTIPLIER: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  very: 1.725,
  extra: 1.9,
};

const PACE_DEFICIT: Record<WeeklyPace, number> = {
  kg025: 275,
  kg050: 550,
  kg100: 750,
};

export function ageFromDob(dateOfBirth: string, onDay = new Date()): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateOfBirth);
  if (!match) return 30;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  let age = onDay.getFullYear() - year;
  const beforeBirthday =
    onDay.getMonth() + 1 < month || (onDay.getMonth() + 1 === month && onDay.getDate() < day);
  if (beforeBirthday) age -= 1;
  return Math.max(0, age);
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
