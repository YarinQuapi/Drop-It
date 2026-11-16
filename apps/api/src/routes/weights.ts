import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { weightTrend } from "../domain.js";
import { asyncRoute } from "../http.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { weightGoalSchema, weightSchema } from "../schemas.js";
import { jerusalemDay } from "../time.js";

export const weightsRouter = Router();
weightsRouter.use(requireUser);

/** Weigh-ins plus the goal and how the user is trending towards it. */
async function weightOverview(userId: string) {
  const [rows, goal] = await Promise.all([
    prisma.weightEntry.findMany({ where: { userId }, orderBy: { loggedAt: "asc" } }),
    prisma.weightGoal.findUnique({ where: { userId } }),
  ]);
  const weights = rows.map((entry) => ({
    id: entry.id,
    weightKg: num(entry.weightKg),
    loggedAt: entry.loggedAt.toISOString(),
    source: entry.source,
  }));
  if (!goal) return { weights, goal: null, trend: null };
  const trend = weightTrend({
    weights: rows.map((entry) => ({ loggedAt: entry.loggedAt, weightKg: num(entry.weightKg) })),
    targetKg: num(goal.targetKg),
    startKg: num(goal.startKg),
    now: new Date(),
  });
  return {
    weights,
    goal: { targetKg: num(goal.targetKg), startKg: num(goal.startKg), setAt: goal.setAt.toISOString() },
    trend: {
      status: trend.status,
      currentKg: trend.currentKg,
      remainingKg: trend.remainingKg,
      progress: trend.progress,
      ratePerWeekKg: trend.ratePerWeekKg,
      etaAt: trend.etaAt?.toISOString() ?? null,
      etaDay: trend.etaAt ? jerusalemDay(trend.etaAt) : null,
      line: trend.line && {
        fromAt: trend.line.fromAt.toISOString(),
        fromKg: trend.line.fromKg,
        perDayKg: trend.line.perDayKg,
      },
    },
  };
}

weightsRouter.get(
  "/",
  requirePermission("weights:read"),
  asyncRoute(async (_req, res) => {
    res.json(await weightOverview(currentUser(res).id));
  }),
);

weightsRouter.post(
  "/",
  requirePermission("weights:create"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = weightSchema.parse(req.body);
    const entry = await prisma.weightEntry.create({
      data: {
        userId: user.id,
        weightKg: body.weightKg,
        loggedAt: body.loggedAt ? new Date(body.loggedAt) : new Date(),
      },
    });
    res.status(201).json({
      weight: {
        id: entry.id,
        weightKg: num(entry.weightKg),
        loggedAt: entry.loggedAt.toISOString(),
        source: entry.source,
      },
    });
  }),
);

weightsRouter.put(
  "/goal",
  requirePermission("weights:create"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = weightGoalSchema.parse(req.body);
    const [existing, latest, profile] = await Promise.all([
      prisma.weightGoal.findUnique({ where: { userId: user.id } }),
      prisma.weightEntry.findFirst({
        where: { userId: user.id, loggedAt: { lte: new Date() } },
        orderBy: { loggedAt: "desc" },
      }),
      prisma.profile.findUnique({ where: { userId: user.id } }),
    ]);
    // Moving the target further along the same way keeps the progress made so far;
    // a goal in the other direction (or a first goal) starts from today's weight.
    const sameWay =
      existing != null &&
      Math.sign(body.targetKg - num(existing.startKg)) === Math.sign(num(existing.targetKg) - num(existing.startKg)) &&
      body.targetKg !== num(existing.startKg);
    if (sameWay) {
      await prisma.weightGoal.update({ where: { userId: user.id }, data: { targetKg: body.targetKg } });
    } else {
      const startKg = latest ? num(latest.weightKg) : profile ? num(profile.weightKg) : body.targetKg;
      await prisma.weightGoal.upsert({
        where: { userId: user.id },
        create: { userId: user.id, targetKg: body.targetKg, startKg },
        update: { targetKg: body.targetKg, startKg, setAt: new Date() },
      });
    }
    res.json(await weightOverview(user.id));
  }),
);

weightsRouter.delete(
  "/goal",
  requirePermission("weights:create"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    await prisma.weightGoal.deleteMany({ where: { userId: user.id } });
    res.json(await weightOverview(user.id));
  }),
);
