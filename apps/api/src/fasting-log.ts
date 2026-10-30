import { prisma } from "./db.js";

type FastingDb = Pick<typeof prisma, "fastingTimer" | "fastingSession">;

export async function closeRunningFast(db: FastingDb, userId: string, at = new Date()) {
  const timer = await db.fastingTimer.findUnique({ where: { userId } });
  if (!timer?.startedAt || timer.stoppedAt) return timer;
  const closed = await db.fastingSession.updateMany({
    where: { userId, endedAt: null },
    data: { endedAt: at },
  });
  if (closed.count === 0) {
    await db.fastingSession.create({
      data: {
        userId,
        startedAt: timer.startedAt,
        endedAt: at,
        lengthHours: timer.lengthHours ?? 16,
      },
    });
  }
  return db.fastingTimer.update({
    where: { userId },
    data: { stoppedAt: at },
  });
}
