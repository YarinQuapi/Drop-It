import { createHash } from "node:crypto";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { HttpError } from "./http.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export type AppleIdentity = {
  sub: string;
  email: string | null;
  emailVerified: boolean;
};

export type AppleConfig = {
  enabled: boolean;
  servicesId: string | null;
  redirectUri: string | null;
};

export function appleAudiences(): string[] {
  return [process.env.APPLE_IOS_BUNDLE_ID ?? "com.dropit.dropIt", process.env.APPLE_SERVICES_ID].filter(
    (value): value is string => typeof value === "string" && value.length > 0,
  );
}

export function appleConfig(): AppleConfig {
  const servicesId = process.env.APPLE_SERVICES_ID || null;
  const redirectUri = process.env.APPLE_REDIRECT_URI || null;
  return { enabled: servicesId != null && redirectUri != null, servicesId, redirectUri };
}

export function hashNonce(rawNonce: string): string {
  return createHash("sha256").update(rawNonce).digest("hex");
}

/** Apple sends email_verified as a boolean or the strings "true"/"false". */
export function claimIsTrue(value: unknown): boolean {
  return value === true || value === "true";
}

export function identityFromClaims(claims: Record<string, unknown>, rawNonce: string): AppleIdentity {
  if (typeof claims.sub !== "string" || claims.sub.length === 0) throw new HttpError(401, "apple_failed");
  if (claims.nonce !== hashNonce(rawNonce)) throw new HttpError(401, "apple_failed");
  const email = typeof claims.email === "string" && claims.email.length > 0 ? claims.email.toLowerCase() : null;
  return { sub: claims.sub, email, emailVerified: email != null && claimIsTrue(claims.email_verified) };
}

export async function verifyAppleToken(identityToken: string, rawNonce: string): Promise<AppleIdentity> {
  const audience = appleAudiences();
  if (audience.length === 0) throw new HttpError(503, "apple_unavailable");
  try {
    const { payload } = await jwtVerify(identityToken, APPLE_JWKS, { issuer: APPLE_ISSUER, audience });
    return identityFromClaims(payload as Record<string, unknown>, rawNonce);
  } catch (err) {
    if (err instanceof HttpError) throw err;
    throw new HttpError(401, "apple_failed");
  }
}

export type AppleUserStore<U extends { id: string }> = {
  findBySub(sub: string): Promise<U | null>;
  findByEmail(email: string): Promise<U | null>;
  linkSub(userId: string, sub: string): Promise<U>;
  create(email: string): Promise<U>;
};

/**
 * Returning sub -> sign in. Verified email matching an existing account -> link it.
 * Unverified email matching an existing account -> refuse. Otherwise create a new account.
 */
export async function resolveAppleUser<U extends { id: string }>(
  identity: AppleIdentity,
  store: AppleUserStore<U>,
): Promise<{ user: U; created: boolean }> {
  const bySub = await store.findBySub(identity.sub);
  if (bySub) return { user: bySub, created: false };

  if (identity.email) {
    const byEmail = await store.findByEmail(identity.email);
    if (byEmail) {
      if (!identity.emailVerified) throw new HttpError(409, "apple_unverified_email");
      return { user: await store.linkSub(byEmail.id, identity.sub), created: false };
    }
  }

  // Apple can omit the email on later sign-ins; a first sign-in without one cannot create an account.
  if (!identity.email) throw new HttpError(400, "apple_no_email");
  return { user: await store.create(identity.email), created: true };
}
