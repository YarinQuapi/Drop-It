import type { NextFunction, Request, Response } from "express";
import { currentUser } from "./auth.js";
import { prisma } from "./db.js";
import { HttpError } from "./http.js";

export const OPERATIONS = [
  "profile:read",
  "profile:update",
  "settings:update",
  "days:read",
  "entries:create",
  "entries:delete",
  "foods:read",
  "foods:create",
  "foods:update",
  "foods:publish",
  "foods:verify",
  "weeks:read",
  "weights:read",
  "weights:create",
  "fasting:read",
  "fasting:update",
  "fasting:timer",
] as const;

export type Operation = (typeof OPERATIONS)[number];

export const DEFAULT_USER_PERMISSIONS: Record<Operation, boolean> = {
  "profile:read": true,
  "profile:update": true,
  "settings:update": true,
  "days:read": true,
  "entries:create": true,
  "entries:delete": true,
  "foods:read": true,
  "foods:create": true,
  "foods:update": true,
  "foods:publish": true,
  "foods:verify": false,
  "weeks:read": true,
  "weights:read": true,
  "weights:create": true,
  "fasting:read": true,
  "fasting:update": true,
  "fasting:timer": true,
};

export function resolvePermissions(
  isAdmin: boolean,
  overrides: { operation: string; allowed: boolean }[],
): Record<Operation, boolean> {
  if (isAdmin) {
    const all = {} as Record<Operation, boolean>;
    for (const op of OPERATIONS) all[op] = true;
    return all;
  }
  const map: Record<Operation, boolean> = { ...DEFAULT_USER_PERMISSIONS };
  for (const row of overrides) {
    if (row.operation in map) {
      map[row.operation as Operation] = row.allowed;
    }
  }
  return map;
}

export async function getUserPermissionsMap(): Promise<Record<Operation, boolean>> {
  const rows = await prisma.rolePermission.findMany({ where: { role: "user" } });
  return resolvePermissions(false, rows);
}

export async function getAllowedOperations(isAdmin: boolean): Promise<Operation[]> {
  if (isAdmin) return [...OPERATIONS];
  const map = await getUserPermissionsMap();
  return OPERATIONS.filter((op) => map[op]);
}

export function requireAdmin(_req: Request, res: Response, next: NextFunction): void {
  try {
    const user = currentUser(res);
    if (!user.isAdmin) throw new HttpError(403, "forbidden");
    next();
  } catch (err) {
    next(err);
  }
}

export function requirePermission(operation: Operation) {
  return async (_req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const user = currentUser(res);
      if (user.isAdmin) {
        next();
        return;
      }
      const row = await prisma.rolePermission.findUnique({
        where: { role_operation: { role: "user", operation } },
      });
      const allowed = row ? row.allowed : DEFAULT_USER_PERMISSIONS[operation];
      if (!allowed) throw new HttpError(403, "forbidden");
      next();
    } catch (err) {
      next(err);
    }
  };
}
