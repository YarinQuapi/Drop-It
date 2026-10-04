import argon2 from "argon2";
import { Router } from "express";
import { currentUser, newSessionToken, requireUser, sessionCookieName } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute, HttpError } from "../http.js";
import { loginSchema, signupSchema } from "../schemas.js";

export const authRouter = Router();

function publicUser(user: {
  id: string;
  email: string;
  language: "en" | "he";
  isAdmin: boolean;
  autoPublishFoods: boolean;
}) {
  return user;
}

authRouter.post(
  "/signup",
  asyncRoute(async (req, res) => {
    const body = signupSchema.parse(req.body);
    const email = body.email.toLowerCase();
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) throw new HttpError(409, "email_taken");
    const passwordHash = await argon2.hash(body.password);
    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        language: body.language ?? "en",
        fastingSettings: { create: {} },
        fastingTimer: { create: {} },
      },
    });
    const session = newSessionToken();
    await prisma.session.create({
      data: { userId: user.id, tokenHash: session.tokenHash, expiresAt: session.expiresAt },
    });
    res.cookie(sessionCookieName(), session.token, cookieOptions(session.expiresAt));
    res.status(201).json({
      token: session.token,
      user: publicUser(user),
    });
  }),
);

authRouter.post(
  "/login",
  asyncRoute(async (req, res) => {
    const body = loginSchema.parse(req.body);
    const user = await prisma.user.findUnique({ where: { email: body.email.toLowerCase() } });
    if (!user || !(await argon2.verify(user.passwordHash, body.password))) {
      throw new HttpError(401, "invalid_login");
    }
    const session = newSessionToken();
    await prisma.session.create({
      data: { userId: user.id, tokenHash: session.tokenHash, expiresAt: session.expiresAt },
    });
    res.cookie(sessionCookieName(), session.token, cookieOptions(session.expiresAt));
    res.json({ token: session.token, user: publicUser(user) });
  }),
);

authRouter.post(
  "/logout",
  requireUser,
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    await prisma.session.deleteMany({ where: { userId: user.id } });
    res.clearCookie(sessionCookieName());
    res.json({ ok: true });
  }),
);

authRouter.get(
  "/me",
  requireUser,
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const [profile, fasting] = await Promise.all([
      prisma.profile.findUnique({ where: { userId: user.id } }),
      prisma.fastingSettings.findUnique({ where: { userId: user.id } }),
    ]);
    res.json({
      user,
      hasProfile: profile != null,
      fastingEnabled: fasting?.enabled ?? false,
    });
  }),
);

function cookieOptions(expires: Date) {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: false,
    path: "/",
    expires,
  };
}
