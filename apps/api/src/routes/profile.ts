import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute } from "../http.js";
import { ensureGoal } from "../goals.js";
import { num } from "../present.js";
import { profileSchema, settingsSchema } from "../schemas.js";
import { dayToUtcDate, todayJerusalem, utcDateToDay } from "../time.js";

export const profileRouter = Router();
profileRouter.use(requireUser);

profileRouter.get(
  "/",
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const profile = await prisma.profile.findUnique({ where: { userId: user.id } });
    if (!profile) {
      res.json({ profile: null, goalKcal: null });
      return;
    }
    const today = todayJerusalem();
    const goalKcal = await ensureGoal(user.id, today);
    res.json({ profile: presentProfile(profile), goalKcal });
  }),
);

profileRouter.put(
  "/",
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
    const goalKcal = await ensureGoal(user.id, todayJerusalem(), true);
    res.json({ profile: presentProfile(profile), goalKcal });
  }),
);

profileRouter.get(
  "/settings",
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const fresh = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    res.json({ language: fresh.language, autoPublishFoods: fresh.autoPublishFoods });
  }),
);

profileRouter.put(
  "/settings",
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
