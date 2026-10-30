import { Router } from "express";
import { z } from "zod";
import { requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute } from "../http.js";
import { getUserPermissionsMap, OPERATIONS, type Operation, requireAdmin } from "../rbac.js";

const permissionsUpdateSchema = z.object({
  permissions: z.record(z.enum(OPERATIONS), z.boolean()),
});

export const rbacRouter = Router();
rbacRouter.use(requireUser, requireAdmin);

rbacRouter.get(
  "/permissions",
  asyncRoute(async (_req, res) => {
    const permissions = await getUserPermissionsMap();
    res.json({ operations: OPERATIONS, permissions });
  }),
);

rbacRouter.put(
  "/permissions",
  asyncRoute(async (req, res) => {
    const body = permissionsUpdateSchema.parse(req.body);
    const entries = Object.entries(body.permissions) as [Operation, boolean][];
    if (entries.length > 0) {
      await prisma.$transaction(
        entries.map(([operation, allowed]) =>
          prisma.rolePermission.upsert({
            where: { role_operation: { role: "user", operation } },
            create: { role: "user", operation, allowed },
            update: { allowed },
          }),
        ),
      );
    }
    const permissions = await getUserPermissionsMap();
    res.json({ operations: OPERATIONS, permissions });
  }),
);
