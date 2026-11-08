import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import {
  calorieSafetyFloor,
  suggestedCalorieGoal,
  weightForGoal,
  type ActivityLevel,
  type Sex,
  type WeeklyPace,
} from "../domain.js";
import { asyncRoute } from "../http.js";
import { ensureGoal, resolveGoal, suggestedGoalFromProfile } from "../goals.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { profileSchema, settingsSchema } from "../schemas.js";
import { ageOn, dayToUtcDate, firstOfMonth, jerusalemDay, todayJerusalem, utcDateToDay } from "../time.js";

export const profileRouter = Router();
profileRouter.use(requireUser);

profileRouter.get(
  "/",
  requirePermission("profile:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const profile = await prisma.profile.findUnique({ where: { userId: user.id } });
    if (!profile) {
      res.json({ profile: null, goalKcal: null, suggestedGoalKcal: null });
      return;
    }
    const today = todayJerusalem();
    const weights = await prisma.weightEntry.findMany({ where: { userId: user.id } });
    const weighIns = weights.map((entry) => ({
      loggedAt: entry.loggedAt,
      weightKg: entry.weightKg.toNumber(),
    }));
    const goal = await resolveGoal(user.id, today, { future: false });
    res.json({
      profile: presentProfile(profile),
      goalKcal: goal?.goalKcal ?? null,
      suggestedGoalKcal: suggestedGoalFromProfile(profile, today, weighIns),
    });
  }),
);

profileRouter.put(
  "/",
  requirePermission("profile:update"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = profileSchema.parse(req.body);
    const today = todayJerusalem();
    const weights = await prisma.weightEntry.findMany({ where: { userId: user.id } });
    const weighIns = weights.map((entry) => ({
      loggedAt: entry.loggedAt,
      weightKg: entry.weightKg.toNumber(),
    }));
    const weightKg = weightForGoal({
      day: today,
      profileWeightKg: body.weightKg,
      weighIns,
      jerusalemDay,
      firstOfMonth,
    });
    const age = ageOn(body.dateOfBirth, today);
    const person = {
      sex: body.sex as Sex,
      weightKg,
      heightCm: body.heightCm,
      age,
      activity: body.activity as ActivityLevel,
      pace: body.weeklyPace as WeeklyPace,
    };
    const floor = calorieSafetyFloor(person);
    const suggested = suggestedCalorieGoal(person);

    let customGoalKcal: number | null = null;
    if (body.customGoalKcal !== undefined && body.customGoalKcal !== null) {
      const clamped = Math.max(body.customGoalKcal, floor);
      customGoalKcal = clamped === suggested ? null : clamped;
    }

    const profile = await prisma.profile.upsert({
      where: { userId: user.id },
      create: {
        userId: user.id,
        sex: body.sex,
        dateOfBirth: dayToUtcDate(body.dateOfBirth),
        heightCm: body.heightCm,
        weightKg: body.weightKg,
        activity: body.activity,
        weeklyPace: body.weeklyPace,
        customGoalKcal,
      },
      update: {
        sex: body.sex,
        dateOfBirth: dayToUtcDate(body.dateOfBirth),
        heightCm: body.heightCm,
        weightKg: body.weightKg,
        activity: body.activity,
        weeklyPace: body.weeklyPace,
        customGoalKcal,
      },
    });
    // The first weight a user gives (usually during onboarding) starts their weight graph.
    if (weights.length === 0) {
      await prisma.weightEntry.create({ data: { userId: user.id, weightKg: body.weightKg, loggedAt: new Date() } });
    }
    await ensureGoal(user.id, today, true);
    const goal = await resolveGoal(user.id, today, { future: false });
    res.json({
      profile: presentProfile(profile),
      goalKcal: goal?.goalKcal ?? null,
      suggestedGoalKcal: suggested,
    });
  }),
);

profileRouter.get(
  "/settings",
  requirePermission("profile:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const fresh = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    res.json({ language: fresh.language, autoPublishFoods: fresh.autoPublishFoods });
  }),
);

profileRouter.put(
  "/settings",
  requirePermission("settings:update"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = settingsSchema.parse(req.body);
    const fresh = await prisma.user.update({
      where: { id: user.id },
      data: {
        language: body.language,
        autoPublishFoods: body.autoPublishFoods,
      },
    });
    res.json({ language: fresh.language, autoPublishFoods: fresh.autoPublishFoods });
  }),
);

function presentProfile(profile: {
  sex: "male" | "female";
  dateOfBirth: Date;
  heightCm: { toNumber(): number };
  weightKg: { toNumber(): number };
  activity: "sedentary" | "light" | "moderate" | "very" | "extra";
  weeklyPace: "kg025" | "kg050" | "kg100";
  customGoalKcal: number | null;
}) {
  return {
    sex: profile.sex,
    dateOfBirth: utcDateToDay(profile.dateOfBirth),
    heightCm: num(profile.heightCm),
    weightKg: num(profile.weightKg),
    activity: profile.activity,
    weeklyPace: profile.weeklyPace,
    customGoalKcal: profile.customGoalKcal,
  };
}
