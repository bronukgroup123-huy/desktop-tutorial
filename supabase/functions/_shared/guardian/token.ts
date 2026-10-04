// supabase/functions/_shared/guardian/token.ts

import { create, verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import type { GuardianTokenPayload } from "./types.ts";

const JWT_SECRET_ENV = "GUARDIAN_JWT_SECRET";
const TOKEN_TTL_SECONDS = 24 * 60 * 60; // 24 години

function getSecret(): CryptoKey {
  const secret = Deno.env.get(JWT_SECRET_ENV);
  if (!secret || secret.length < 32) {
    throw new Error(
      `${JWT_SECRET_ENV} must be set and at least 32 characters long`
    );
  }
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  ) as unknown as CryptoKey;
}

export interface GeneratedToken {
  token: string;
  tokenHash: string;
  tokenPrefix: string;
  expiresAt: Date;
  jti: string;
}

export async function generateGuardianToken(
  sessionId: string,
  guardianId: string
): Promise<GeneratedToken> {
  const jti = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  const exp = now + TOKEN_TTL_SECONDS;

  const payload: GuardianTokenPayload = {
    session_id: sessionId,
    guardian_id: guardianId,
    role: "guardian",
    iat: now,
    exp,
    jti,
  };

  const secret = await getSecret();
  const token = await create({ alg: "HS256", typ: "JWT" }, payload, secret);

  const tokenHash = await hashToken(token);
  const tokenPrefix = token.slice(0, 8);

  return {
    token,
    tokenHash,
    tokenPrefix,
    expiresAt: new Date(exp * 1000),
    jti,
  };
}

export interface TokenValidationResult {
  valid: boolean;
  payload?: GuardianTokenPayload;
  error?: string;
}

export async function validateGuardianToken(
  token: string
): Promise<TokenValidationResult> {
  try {
    const secret = await getSecret();
    const payload = await verify(
      token,
      secret
    ) as unknown as GuardianTokenPayload;

    if (payload.role !== "guardian") {
      return { valid: false, error: "Invalid role" };
    }

    if (payload.exp < Math.floor(Date.now() / 1000)) {
      return { valid: false, error: "Token expired" };
    }

    return { valid: true, payload };
  } catch (err) {
    return {
      valid: false,
      error: err instanceof Error ? err.message : "Unknown error",
    };
  }
}

export async function hashToken(token: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(token);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

const GUARDIAN_BASE_URL =
  Deno.env.get("GUARDIAN_BASE_URL") ??
  "https://guardian.mushroomradar.com.ua";

export function buildGuardianUrl(token: string): string {
  return `${GUARDIAN_BASE_URL}/s/${token}`;
}
