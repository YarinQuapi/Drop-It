import { api, ApiError, type Me } from "./api";

export type AppleConfig = { enabled: boolean; servicesId: string | null; redirectUri: string | null };

type AppleSignInResult = { authorization: { id_token: string } };
type AppleIdGlobal = {
  auth: {
    init(config: {
      clientId: string;
      scope: string;
      redirectURI: string;
      state: string;
      nonce: string;
      usePopup: boolean;
    }): void;
    signIn(): Promise<AppleSignInResult>;
  };
};

declare global {
  interface Window {
    AppleID?: AppleIdGlobal;
  }
}

const SCRIPT_URL = "https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js";
let scriptPromise: Promise<void> | null = null;

function loadAppleScript(): Promise<void> {
  if (window.AppleID) return Promise.resolve();
  scriptPromise ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = SCRIPT_URL;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => {
      scriptPromise = null;
      reject(new ApiError("apple_failed"));
    };
    document.head.appendChild(script);
  });
  return scriptPromise;
}

export async function fetchAppleConfig(): Promise<AppleConfig> {
  try {
    return await api<AppleConfig>("/api/auth/apple/config");
  } catch {
    return { enabled: false, servicesId: null, redirectUri: null };
  }
}

function randomNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** Runs the Apple popup, exchanges the identity token with the API, and returns the signed-in user. */
export async function signInWithApple(config: AppleConfig, language: "en" | "he"): Promise<Me> {
  if (!config.enabled || !config.servicesId || !config.redirectUri) throw new ApiError("apple_unavailable");
  await loadAppleScript();
  const rawNonce = randomNonce();
  const hashedNonce = await sha256Hex(rawNonce);
  const apple = window.AppleID;
  if (!apple) throw new ApiError("apple_failed");
  apple.auth.init({
    clientId: config.servicesId,
    scope: "name email",
    redirectURI: config.redirectUri,
    state: randomNonce(),
    nonce: hashedNonce,
    usePopup: true,
  });
  let result: AppleSignInResult;
  try {
    result = await apple.auth.signIn();
  } catch (err) {
    const code = (err as { error?: string } | null)?.error;
    throw new ApiError(code === "popup_closed_by_user" || code === "user_cancelled_authorize" ? "apple_cancelled" : "apple_failed");
  }
  await api("/api/auth/apple", {
    method: "POST",
    body: JSON.stringify({ identityToken: result.authorization.id_token, nonce: rawNonce, language }),
  });
  return api<Me>("/api/auth/me");
}
