import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute } from "../http.js";
import { ensureGoal, resolveGoal } from "../goals.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { profileSchema, settingsSchema } from "../schemas.js";
import { dayToUtcDate, todayJerusalem, utcDateToDay } from "../time.js";

export const profileRouter = Router();
profileRouter.use(requireUser);

profileRouter.get(
  "/",
  requirePermission("profile:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const profile = await prisma.profile.findUnique({ where: { userId: user.id } });
    if (!profile) {
      res.json({ profile: null, goalKcal: null });
      return;
    }
    const goal = await resolveGoal(user.id, todayJerusalem(), { future: false });
    res.json({ profile: presentProfile(profile), goalKcal: goal?.goalKcal ?? null });
  }),
);

profileRouter.put(
  "/",
  requirePermission("profile:update"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = profileSchema.parse(req.body);
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
      },
      update: {
        sex: body.sex,
        dateOfBirth: dayToUtcDate(body.dateOfBirth),
        heightCm: body.heightCm,
        weightKg: body.weightKg,
        activity: body.activity,
        weeklyPace: body.weeklyPace,
      },
    });
    await ensureGoal(user.id, todayJerusalem(), true);
    const goal = await resolveGoal(user.id, todayJerusalem(), { future: false });
    res.json({ profile: presentProfile(profile), goalKcal: goal?.goalKcal ?? null });
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
}) {
  return {
    sex: profile.sex,
    dateOfBirth: utcDateToDay(profile.dateOfBirth),
    heightCm: num(profile.heightCm),
    weightKg: num(profile.weightKg),
    activity: profile.activity,
    weeklyPace: profile.weeklyPace,
  };
}
