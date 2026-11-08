import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute } from "../http.js";
import { ensureGoal, loadHealthSettings, type HealthContext } from "../goals.js";
import { requirePermission } from "../rbac.js";
import { healthSettingsSchema, healthSyncSchema } from "../schemas.js";
import { compareDays, dayToUtcDate, isDayString, todayJerusalem } from "../time.js";

export const appleHealthRouter = Router();
appleHealthRouter.use(requireUser);

appleHealthRouter.get(
  "/",
  requirePermission("appleHealth:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    res.json(presentSettings(await loadHealthSettings(user.id)));
  }),
);

appleHealthRouter.put(
  "/settings",
  requirePermission("appleHealth:sync"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = healthSettingsSchema.parse(req.body);
    await prisma.healthSettings.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...body },
      update: body,
    });
    res.json(presentSettings(await loadHealthSettings(user.id)));
  }),
);

appleHealthRouter.post(
  "/sync",
  requirePermission("appleHealth:sync"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = healthSyncSchema.parse(req.body);
    const today = todayJerusalem();
    const before = await loadHealthSettings(user.id);
    const now = new Date();
    const days = body.days.filter((entry) => isDayString(entry.day) && compareDays(entry.day, today) <= 0);

    await prisma.$transaction(async (tx) => {
      // Samples are immutable in HealthKit (an edit is a delete plus a new sample), so a
      // duplicate externalId can safely be skipped.
      if (body.weights.length > 0) {
        await tx.weightEntry.createMany({
          data: body.weights.map((sample) => ({
            userId: user.id,
            weightKg: sample.weightKg,
            loggedAt: new Date(sample.loggedAt),
            source: "health" as const,
            externalId: sample.externalId,
          })),
          skipDuplicates: true,
        });
      }
      if (body.deletedWeightIds.length > 0) {
        await tx.weightEntry.deleteMany({
          where: { userId: user.id, source: "health", externalId: { in: body.deletedWeightIds } },
        });
      }
      for (const entry of days) {
        const values = {
          steps: Math.round(entry.steps),
          exerciseMinutes: Math.round(entry.exerciseMinutes),
          activeKcal: Math.round(entry.activeKcal),
        };
        await tx.healthDay.upsert({
          where: { userId_day: { userId: user.id, day: dayToUtcDate(entry.day) } },
          create: { userId: user.id, day: dayToUtcDate(entry.day), ...values },
          update: { ...values, syncedAt: now },
        });
      }
      await tx.healthSettings.upsert({
        where: { userId: user.id },
        create: { userId: user.id, connected: true, connectedOn: dayToUtcDate(today), lastSyncedAt: now },
        update: before.connected
          ? { lastSyncedAt: now }
          : { connected: true, connectedOn: dayToUtcDate(today), lastSyncedAt: now },
      });
    });

    // Connecting freezes today as the sedentary base. Later syncs update activity without raising the food budget.
    if (!before.connected) await ensureGoal(user.id, today, true);
    res.json(presentSettings(await loadHealthSettings(user.id)));
  }),
);

appleHealthRouter.post(
  "/disconnect",
  requirePermission("appleHealth:sync"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    await prisma.healthSettings.upsert({
      where: { userId: user.id },
      create: { userId: user.id, connected: false },
      update: { connected: false },
    });
    // Today returns to the profile activity estimate. Earlier days keep what they froze.
    await ensureGoal(user.id, todayJerusalem(), true);
    res.json(presentSettings(await loadHealthSettings(user.id)));
  }),
);

function presentSettings(settings: HealthContext) {
  return {
    connected: settings.connected,
    connectedOn: settings.connectedOn,
    lastSyncedAt: settings.lastSyncedAt ? settings.lastSyncedAt.toISOString() : null,
    exerciseGoalMinutes: settings.exerciseGoalMinutes,
    stepGoal: settings.stepGoal,
  };
}
