import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { approximateEndHour, fastDurationMinutes, fastEndsAt } from "../domain.js";
import { closeRunningFast } from "../fasting-log.js";
import { asyncRoute, HttpError } from "../http.js";
import { requirePermission } from "../rbac.js";
import { fastingSchema } from "../schemas.js";

export const fastingRouter = Router();
fastingRouter.use(requireUser);

fastingRouter.get(
  "/",
  requirePermission("fasting:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    res.json(await loadState(user.id));
  }),
);

fastingRouter.put(
  "/",
  requirePermission("fasting:update"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = fastingSchema.parse(req.body);
    const saved = { ...body, endHour: approximateEndHour(body.startHour, body.lengthHours) };
    await prisma.fastingSettings.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...saved },
      update: saved,
    });
    if (!body.enabled) await closeRunningFast(prisma, user.id);
    res.json(await loadState(user.id));
  }),
);

fastingRouter.post(
  "/start",
  requirePermission("fasting:timer"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const settings = await prisma.fastingSettings.findUnique({ where: { userId: user.id } });
    if (!settings?.enabled) throw new HttpError(400, "fasting_disabled");
    const existing = await prisma.fastingTimer.findUnique({ where: { userId: user.id } });
    if (existing?.startedAt && !existing.stoppedAt) throw new HttpError(409, "timer_running");
    const startedAt = new Date();
    await prisma.$transaction([
      prisma.fastingTimer.upsert({
        where: { userId: user.id },
        create: {
          userId: user.id,
          startedAt,
          lengthHours: settings.lengthHours,
          stoppedAt: null,
        },
        update: {
          startedAt,
          lengthHours: settings.lengthHours,
          stoppedAt: null,
        },
      }),
      prisma.fastingSession.create({
        data: {
          userId: user.id,
          startedAt,
          lengthHours: settings.lengthHours,
        },
      }),
    ]);
    res.json(await loadState(user.id));
  }),
);

fastingRouter.post(
  "/stop",
  requirePermission("fasting:timer"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    await closeRunningFast(prisma, user.id);
    res.json(await loadState(user.id));
  }),
);

async function loadState(userId: string) {
  const [settings, timer] = await Promise.all([
    prisma.fastingSettings.findUnique({ where: { userId } }),
    prisma.fastingTimer.findUnique({ where: { userId } }),
  ]);
  if (timer?.startedAt && !timer.stoppedAt) {
    const open = await prisma.fastingSession.findFirst({ where: { userId, endedAt: null } });
    if (!open) {
      await prisma.fastingSession.create({
        data: {
          userId,
          startedAt: timer.startedAt,
          lengthHours: timer.lengthHours ?? settings?.lengthHours ?? 16,
        },
      });
    }
  }
  const sessions = await prisma.fastingSession.findMany({
    where: { userId },
    orderBy: { startedAt: "desc" },
    take: 100,
  });
  return present(settings, timer, sessions);
}

function present(
  settings: { enabled: boolean; lengthHours: number; startHour: number; endHour: number } | null,
  timer: { startedAt: Date | null; lengthHours: number | null; stoppedAt: Date | null } | null,
  sessions: { id: string; startedAt: Date; endedAt: Date | null; lengthHours: number }[],
) {
  const running = Boolean(timer?.startedAt && !timer.stoppedAt && timer.lengthHours);
  const endsAt =
    running && timer?.startedAt && timer.lengthHours ? fastEndsAt(timer.startedAt, timer.lengthHours) : null;
  return {
    enabled: settings?.enabled ?? false,
    lengthHours: settings?.lengthHours ?? 16,
    startHour: settings?.startHour ?? 20,
    endHour: settings ? approximateEndHour(settings.startHour, settings.lengthHours) : 12,
    running,
    startedAt: running ? timer?.startedAt?.toISOString() ?? null : null,
    endsAt: endsAt?.toISOString() ?? null,
    lengthHoursRunning: running ? timer?.lengthHours ?? null : null,
    sessions: sessions.map((session) => ({
      id: session.id,
      startedAt: session.startedAt.toISOString(),
      endedAt: session.endedAt?.toISOString() ?? null,
      endsAt: fastEndsAt(session.startedAt, session.lengthHours).toISOString(),
      lengthHours: session.lengthHours,
      running: session.endedAt == null,
      durationMinutes: session.endedAt ? fastDurationMinutes(session.startedAt, session.endedAt) : null,
    })),
  };
}
