import argon2 from "argon2";
import { Router, type Response } from "express";
import { appleConfig, resolveAppleUser, verifyAppleToken } from "../apple.js";
import { currentUser, hashToken, newSessionToken, readToken, requireUser, sessionCookieName } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute, HttpError } from "../http.js";
import { getAllowedOperations } from "../rbac.js";
import { appleSignInSchema, changePasswordSchema, loginSchema, signupSchema } from "../schemas.js";

export const authRouter = Router();

function publicUser(user: {
  id: string;
  email: string;
  language: "en" | "he";
  isAdmin: boolean;
  autoPublishFoods: boolean;
}) {
  return {
    id: user.id,
    email: user.email,
    language: user.language,
    isAdmin: user.isAdmin,
    autoPublishFoods: user.autoPublishFoods,
  };
}

async function issueSession(
  res: Response,
  user: Parameters<typeof publicUser>[0],
  status = 200,
): Promise<void> {
  const session = newSessionToken();
  await prisma.session.create({
    data: { userId: user.id, tokenHash: session.tokenHash, expiresAt: session.expiresAt },
  });
  const permissions = await getAllowedOperations(user.isAdmin);
  res.cookie(sessionCookieName(), session.token, cookieOptions(session.expiresAt));
  res.status(status).json({ token: session.token, user: publicUser(user), permissions });
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
    await issueSession(res, user, 201);
  }),
);

authRouter.post(
  "/login",
  asyncRoute(async (req, res) => {
    const body = loginSchema.parse(req.body);
    const user = await prisma.user.findUnique({ where: { email: body.email.toLowerCase() } });
    if (!user || !user.passwordHash || !(await argon2.verify(user.passwordHash, body.password))) {
      throw new HttpError(401, "invalid_login");
    }
    await issueSession(res, user);
  }),
);

authRouter.get("/apple/config", (_req, res) => {
  res.json(appleConfig());
});

authRouter.post(
  "/apple",
  asyncRoute(async (req, res) => {
    const body = appleSignInSchema.parse(req.body);
    const identity = await verifyAppleToken(body.identityToken, body.nonce);
    const { user, created } = await resolveAppleUser(identity, {
      findBySub: (sub) => prisma.user.findUnique({ where: { appleSub: sub } }),
      findByEmail: (email) => prisma.user.findUnique({ where: { email } }),
      linkSub: (userId, sub) => prisma.user.update({ where: { id: userId }, data: { appleSub: sub } }),
      create: (email) =>
        prisma.user.create({
          data: {
            email,
            appleSub: identity.sub,
            language: body.language ?? "en",
            fastingSettings: { create: {} },
            fastingTimer: { create: {} },
          },
        }),
    });
    await issueSession(res, user, created ? 201 : 200);
  }),
);

authRouter.post(
  "/logout",
  requireUser,
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const token = readToken(req);
    if (token) {
      await prisma.session.deleteMany({ where: { userId: user.id, tokenHash: hashToken(token) } });
    } else {
      await prisma.session.deleteMany({ where: { userId: user.id } });
    }
    res.clearCookie(sessionCookieName());
    res.json({ ok: true });
  }),
);

authRouter.get(
  "/me",
  requireUser,
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const [profile, fasting, record, permissions] = await Promise.all([
      prisma.profile.findUnique({ where: { userId: user.id } }),
      prisma.fastingSettings.findUnique({ where: { userId: user.id } }),
      prisma.user.findUniqueOrThrow({ where: { id: user.id }, select: { passwordHash: true } }),
      getAllowedOperations(user.isAdmin),
    ]);
    res.json({
      user,
      hasProfile: profile != null,
      hasPassword: record.passwordHash != null,
      fastingEnabled: fasting?.enabled ?? false,
      permissions,
    });
  }),
);

authRouter.put(
  "/password",
  requireUser,
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = changePasswordSchema.parse(req.body);
    const record = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    if (!record.passwordHash) throw new HttpError(400, "no_password");
    if (!(await argon2.verify(record.passwordHash, body.currentPassword))) {
      throw new HttpError(400, "wrong_password");
    }
    const passwordHash = await argon2.hash(body.newPassword);
    await prisma.user.update({
      where: { id: user.id },
      data: { passwordHash },
    });
    res.json({ ok: true });
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
