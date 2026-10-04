import { createHash, randomBytes } from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import { prisma } from "./db.js";
import { HttpError } from "./http.js";

const COOKIE = "dropit_session";
const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

export type AuthUser = {
  id: string;
  email: string;
  language: "en" | "he";
  isAdmin: boolean;
  autoPublishFoods: boolean;
};

declare global {
  namespace Express {
    interface Locals {
      user?: AuthUser;
    }
  }
}

export function sessionCookieName(): string {
  return COOKIE;
}

export function newSessionToken(): { token: string; tokenHash: string; expiresAt: Date } {
  const token = randomBytes(32).toString("base64url");
  return {
    token,
    tokenHash: hashToken(token),
    expiresAt: new Date(Date.now() + THIRTY_DAYS_MS),
  };
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function readToken(req: Request): string | null {
  const header = req.header("authorization");
  if (header?.toLowerCase().startsWith("bearer ")) {
    return header.slice(7).trim();
  }
  const cookie = req.cookies?.[COOKIE];
  return typeof cookie === "string" && cookie.length > 0 ? cookie : null;
}

export async function requireUser(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const token = readToken(req);
    if (!token) throw new HttpError(401, "unauthorized");
    const session = await prisma.session.findUnique({
      where: { tokenHash: hashToken(token) },
      include: { user: true },
    });
    if (!session || session.expiresAt.getTime() <= Date.now()) {
      throw new HttpError(401, "unauthorized");
    }
    res.locals.user = {
      id: session.user.id,
      email: session.user.email,
      language: session.user.language,
      isAdmin: session.user.isAdmin,
      autoPublishFoods: session.user.autoPublishFoods,
    };
    next();
  } catch (err) {
    next(err);
  }
}

export function currentUser(res: Response): AuthUser {
  if (!res.locals.user) throw new HttpError(401, "unauthorized");
  return res.locals.user;
}
