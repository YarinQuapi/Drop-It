import type { Profile } from "../generated/prisma/client.js";
import { prisma } from "./db.js";
import {
  calorieGoal,
  calorieSafetyFloor,
  effectiveGoalKcal,
  suggestedCalorieGoal,
  usesHealthBase,
  weightForGoal,
  type ActivityLevel,
  type Sex,
  type WeeklyPace,
} from "./domain.js";
import { ageOn, dayToUtcDate, firstOfMonth, jerusalemDay, todayJerusalem, utcDateToDay } from "./time.js";

export const DEFAULT_STEP_GOAL = 10000;
export const DEFAULT_EXERCISE_GOAL_MINUTES = 30;

export type HealthContext = {
  connected: boolean;
  connectedOn: string | null;
  lastSyncedAt: Date | null;
  exerciseGoalMinutes: number;
  stepGoal: number;
};

export type HealthDayRow = { steps: number; exerciseMinutes: number; activeKcal: number };

export async function loadHealthSettings(userId: string): Promise<HealthContext> {
  const row = await prisma.healthSettings.findUnique({ where: { userId } });
  return {
    connected: row?.connected ?? false,
    connectedOn: row?.connectedOn ? utcDateToDay(row.connectedOn) : null,
    lastSyncedAt: row?.lastSyncedAt ?? null,
    exerciseGoalMinutes: row?.exerciseGoalMinutes ?? DEFAULT_EXERCISE_GOAL_MINUTES,
    stepGoal: row?.stepGoal ?? DEFAULT_STEP_GOAL,
  };
}

export async function computeGoalKcal(userId: string, day: string, healthBase = false): Promise<number | null> {
  const profile = await prisma.profile.findUnique({ where: { userId } });
  if (!profile) return null;
  const weights = await prisma.weightEntry.findMany({ where: { userId } });
  return goalFromProfile(
    profile,
    day,
    weights.map((entry) => ({
      loggedAt: entry.loggedAt,
      weightKg: entry.weightKg.toNumber(),
    })),
    healthBase ? "sedentary" : profile.activity,
  );
}

function goalInputs(
  profile: Profile,
  day: string,
  weighIns: { loggedAt: Date; weightKg: number }[],
  activity: ActivityLevel = profile.activity,
) {
  const weightKg = weightForGoal({
    day,
    profileWeightKg: profile.weightKg.toNumber(),
    weighIns,
    jerusalemDay,
    firstOfMonth,
  });
  return {
    sex: profile.sex as Sex,
    weightKg,
    heightCm: profile.heightCm.toNumber(),
    age: ageOn(utcDateToDay(profile.dateOfBirth), day),
    activity,
    pace: profile.weeklyPace as WeeklyPace,
    customGoalKcal: profile.customGoalKcal,
  };
}

export function goalFromProfile(
  profile: Profile,
  day: string,
  weighIns: { loggedAt: Date; weightKg: number }[],
  activity: ActivityLevel = profile.activity,
): number {
  return calorieGoal(goalInputs(profile, day, weighIns, activity));
}

export function suggestedGoalFromProfile(
  profile: Profile,
  day: string,
  weighIns: { loggedAt: Date; weightKg: number }[] = [],
  activity: ActivityLevel = profile.activity,
): number {
  const { customGoalKcal: _ignored, ...input } = goalInputs(profile, day, weighIns, activity);
  return suggestedCalorieGoal(input);
}

export function safetyFloorFromProfile(
  profile: Profile,
  day: string,
  weighIns: { loggedAt: Date; weightKg: number }[] = [],
): number {
  const input = goalInputs(profile, day, weighIns);
  return calorieSafetyFloor(input);
}

async function ensureGoalRow(
  userId: string,
  day: string,
  force: boolean,
): Promise<{ goalKcal: number; healthAdjusted: boolean } | null> {
  const existing = await prisma.dailyGoal.findUnique({
    where: { userId_day: { userId, day: dayToUtcDate(day) } },
  });
  if (existing && !force) {
    const profile = await prisma.profile.findUnique({ where: { userId } });
    if (profile) {
      const weights = await prisma.weightEntry.findMany({ where: { userId } });
      const weighIns = weights.map((entry) => ({
        loggedAt: entry.loggedAt,
        weightKg: entry.weightKg.toNumber(),
      }));
      const floor = safetyFloorFromProfile(profile, day, weighIns);
      if (existing.goalKcal >= floor) {
        return { goalKcal: existing.goalKcal, healthAdjusted: existing.healthAdjusted };
      }
    } else {
      return { goalKcal: existing.goalKcal, healthAdjusted: existing.healthAdjusted };
    }
  }
  const settings = await loadHealthSettings(userId);
  const healthAdjusted = usesHealthBase({
    connected: settings.connected,
    connectedOn: settings.connectedOn,
    day,
    today: todayJerusalem(),
  });
  const goalKcal = await computeGoalKcal(userId, day, healthAdjusted);
  if (goalKcal == null) return null;
  await prisma.dailyGoal.upsert({
    where: { userId_day: { userId, day: dayToUtcDate(day) } },
    create: { userId, day: dayToUtcDate(day), goalKcal, healthAdjusted },
    update: { goalKcal, healthAdjusted },
  });
  return { goalKcal, healthAdjusted };
}

/** Returns the frozen base goal for a day (the sedentary base when the day is health adjusted). */
export async function ensureGoal(userId: string, day: string, force = false): Promise<number | null> {
  const row = await ensureGoalRow(userId, day, force);
  return row?.goalKcal ?? null;
}

export type DayGoal = {
  baseGoalKcal: number;
  activeKcal: number;
  goalKcal: number;
  healthAdjusted: boolean;
  healthSynced: boolean;
  steps: number;
  stepGoal: number;
  exerciseMinutes: number;
  exerciseGoalMinutes: number;
};

/**
 * The goal the UI works with: the frozen base plus, for health-adjusted days, that day's
 * Apple active kcal. Future days use the profile estimate and have no Health data.
 */
export async function resolveGoal(
  userId: string,
  day: string,
  opts: { future: boolean; settings?: HealthContext; healthDay?: HealthDayRow | null },
): Promise<DayGoal | null> {
  const settings = opts.settings ?? (await loadHealthSettings(userId));
  const common = {
    healthSynced: settings.lastSyncedAt != null,
    stepGoal: settings.stepGoal,
    exerciseGoalMinutes: settings.exerciseGoalMinutes,
  };
  if (opts.future) {
    const baseGoalKcal = await computeGoalKcal(userId, day);
    if (baseGoalKcal == null) return null;
    return {
      ...common,
      baseGoalKcal,
      activeKcal: 0,
      goalKcal: baseGoalKcal,
      healthAdjusted: false,
      steps: 0,
      exerciseMinutes: 0,
    };
  }
  const row = await ensureGoalRow(userId, day, false);
  if (!row) return null;
  const healthDay =
    opts.healthDay !== undefined
      ? opts.healthDay
      : await prisma.healthDay.findUnique({ where: { userId_day: { userId, day: dayToUtcDate(day) } } });
  const activeKcal = row.healthAdjusted ? (healthDay?.activeKcal ?? 0) : 0;
  return {
    ...common,
    baseGoalKcal: row.goalKcal,
    activeKcal,
    goalKcal: effectiveGoalKcal(row.goalKcal, activeKcal, row.healthAdjusted),
    healthAdjusted: row.healthAdjusted,
    steps: healthDay?.steps ?? 0,
    exerciseMinutes: healthDay?.exerciseMinutes ?? 0,
  };
}
