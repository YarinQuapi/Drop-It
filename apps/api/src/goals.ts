import type { Profile } from "../generated/prisma/client.js";
import { prisma } from "./db.js";
import { calorieGoal, weightForGoal, type ActivityLevel, type Sex, type WeeklyPace } from "./domain.js";
import { ageOn, dayToUtcDate, firstOfMonth, jerusalemDay, utcDateToDay } from "./time.js";

export async function computeGoalKcal(userId: string, day: string): Promise<number | null> {
  const profile = await prisma.profile.findUnique({ where: { userId } });
  if (!profile) return null;
  const weights = await prisma.weightEntry.findMany({ where: { userId } });
  return goalFromProfile(profile, day, weights.map((entry) => ({
    loggedAt: entry.loggedAt,
    weightKg: entry.weightKg.toNumber(),
  })));
}

export function goalFromProfile(
  profile: Profile,
  day: string,
  weighIns: { loggedAt: Date; weightKg: number }[],
): number {
  const weightKg = weightForGoal({
    day,
    profileWeightKg: profile.weightKg.toNumber(),
    weighIns,
    jerusalemDay,
    firstOfMonth,
  });
  return calorieGoal({
    sex: profile.sex as Sex,
    weightKg,
    heightCm: profile.heightCm.toNumber(),
    age: ageOn(utcDateToDay(profile.dateOfBirth), day),
    activity: profile.activity as ActivityLevel,
    pace: profile.weeklyPace as WeeklyPace,
  });
}

export async function ensureGoal(userId: string, day: string, force = false): Promise<number | null> {
  const existing = await prisma.dailyGoal.findUnique({
    where: { userId_day: { userId, day: dayToUtcDate(day) } },
  });
  if (existing && !force) return existing.goalKcal;
  const goalKcal = await computeGoalKcal(userId, day);
  if (goalKcal == null) return null;
  await prisma.dailyGoal.upsert({
    where: { userId_day: { userId, day: dayToUtcDate(day) } },
    create: { userId, day: dayToUtcDate(day), goalKcal },
    update: { goalKcal },
  });
  return goalKcal;
}
