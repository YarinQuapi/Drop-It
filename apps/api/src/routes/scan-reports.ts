import express, { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute, HttpError } from "../http.js";
import { requireAdmin } from "../rbac.js";
import { MAX_SCAN_PHOTO_BYTES, scanReportSchema } from "../schemas.js";

export const scanReportsRouter = Router();
scanReportsRouter.use(requireUser);

// Photos are far bigger than the 1 MB the rest of the API accepts.
const bigJson = express.json({ limit: "7mb" });

const SELECT = {
  id: true,
  userId: true,
  rawText: true,
  parsed: true,
  note: true,
  language: true,
  resolvedAt: true,
  createdAt: true,
} as const;

// Any signed-in user can report a bad scan.
scanReportsRouter.post(
  "/",
  bigJson,
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = scanReportSchema.parse(req.body);
    const photo = Buffer.from(body.photo, "base64");
    if (photo.length === 0 || photo.length > MAX_SCAN_PHOTO_BYTES) {
      throw new HttpError(400, "invalid_body");
    }
    const report = await prisma.scanReport.create({
      data: {
        userId: user.id,
        photo,
        rawText: body.rawText,
        parsed: body.parsed as object,
        note: body.note,
        language: body.language,
      },
      select: { id: true },
    });
    res.status(201).json({ id: report.id });
  }),
);

scanReportsRouter.get(
  "/",
  requireAdmin,
  asyncRoute(async (req, res) => {
    const open = req.query.status !== "resolved";
    const reports = await prisma.scanReport.findMany({
      where: { resolvedAt: open ? null : { not: null } },
      orderBy: { createdAt: "desc" },
      take: 100,
      select: SELECT,
    });
    res.json({ reports });
  }),
);

scanReportsRouter.get(
  "/:id/photo",
  requireAdmin,
  asyncRoute(async (req, res) => {
    const report = await prisma.scanReport.findUnique({
      where: { id: String(req.params.id) },
      select: { photo: true },
    });
    if (!report) throw new HttpError(404, "not_found");
    res.type("image/jpeg").send(Buffer.from(report.photo));
  }),
);

scanReportsRouter.post(
  "/:id/resolve",
  requireAdmin,
  asyncRoute(async (req, res) => {
    const id = String(req.params.id);
    const found = await prisma.scanReport.findUnique({ where: { id }, select: { id: true } });
    if (!found) throw new HttpError(404, "not_found");
    const report = await prisma.scanReport.update({
      where: { id },
      data: { resolvedAt: new Date() },
      select: SELECT,
    });
    res.json({ report });
  }),
);
