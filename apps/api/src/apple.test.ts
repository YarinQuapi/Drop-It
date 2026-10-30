import assert from "node:assert/strict";
import test from "node:test";
import { claimIsTrue, hashNonce, identityFromClaims, resolveAppleUser, type AppleIdentity, type AppleUserStore } from "./apple.js";
import { HttpError } from "./http.js";

type FakeUser = { id: string; email: string; appleSub: string | null };

function fakeStore(users: FakeUser[]): AppleUserStore<FakeUser> & { users: FakeUser[] } {
  return {
    users,
    async findBySub(sub) {
      return users.find((u) => u.appleSub === sub) ?? null;
    },
    async findByEmail(email) {
      return users.find((u) => u.email === email) ?? null;
    },
    async linkSub(userId, sub) {
      const user = users.find((u) => u.id === userId)!;
      user.appleSub = sub;
      return user;
    },
    async create(email) {
      const user = { id: `u${users.length + 1}`, email, appleSub: null };
      users.push(user);
      return user;
    },
  };
}

const identity = (over: Partial<AppleIdentity> = {}): AppleIdentity => ({
  sub: "apple-1",
  email: "a@example.com",
  emailVerified: true,
  ...over,
});

test("returning apple sub signs in without needing an email", async () => {
  const store = fakeStore([{ id: "u1", email: "a@example.com", appleSub: "apple-1" }]);
  const result = await resolveAppleUser(identity({ email: null, emailVerified: false }), store);
  assert.equal(result.user.id, "u1");
  assert.equal(result.created, false);
});

test("verified email links an existing account", async () => {
  const store = fakeStore([{ id: "u1", email: "a@example.com", appleSub: null }]);
  const result = await resolveAppleUser(identity(), store);
  assert.equal(result.user.id, "u1");
  assert.equal(result.created, false);
  assert.equal(store.users[0].appleSub, "apple-1");
  assert.equal(store.users.length, 1);
});

test("unverified email matching an existing account is refused", async () => {
  const store = fakeStore([{ id: "u1", email: "a@example.com", appleSub: null }]);
  await assert.rejects(
    resolveAppleUser(identity({ emailVerified: false }), store),
    (err) => err instanceof HttpError && err.status === 409 && err.code === "apple_unverified_email",
  );
  assert.equal(store.users[0].appleSub, null);
  assert.equal(store.users.length, 1);
});

test("no matching account creates a new user", async () => {
  const store = fakeStore([]);
  const result = await resolveAppleUser(identity(), store);
  assert.equal(result.created, true);
  assert.equal(result.user.email, "a@example.com");
  assert.equal(store.users.length, 1);
});

test("first sign-in without an email cannot create an account", async () => {
  const store = fakeStore([]);
  await assert.rejects(
    resolveAppleUser(identity({ email: null, emailVerified: false }), store),
    (err) => err instanceof HttpError && err.code === "apple_no_email",
  );
});

test("identity claims require the matching hashed nonce", () => {
  const claims = { sub: "apple-1", email: "A@Example.com", email_verified: "true", nonce: hashNonce("raw-nonce-123") };
  assert.deepEqual(identityFromClaims(claims, "raw-nonce-123"), {
    sub: "apple-1",
    email: "a@example.com",
    emailVerified: true,
  });
  assert.throws(
    () => identityFromClaims(claims, "other-nonce-123"),
    (err) => err instanceof HttpError && err.status === 401,
  );
});

test("email_verified accepts boolean or string", () => {
  assert.equal(claimIsTrue(true), true);
  assert.equal(claimIsTrue("true"), true);
  assert.equal(claimIsTrue("false"), false);
  assert.equal(claimIsTrue(undefined), false);
});
