import { OAuth2Client } from "google-auth-library";
import type { Request } from "express";
import { PROJECT_ID, LOCATION } from "../config/constants";

const authClient = new OAuth2Client();

// エミュレータ判定
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = Buffer.from(parts[1], "base64").toString("utf8");
    return JSON.parse(payload);
  } catch {
    return null;
  }
}

/**
 * Cloud Tasksからのリクエストを検証
 * OIDCトークンを検証し、正当なリクエストかどうかを判定
 *
 * 検証項目:
 * 1. Bearer トークンの存在
 * 2. トークンの署名検証（Google発行であること）
 * 3. audience（呼び出し先関数URL）の一致
 */
export async function verifyCloudTasksRequest(
  request: Request,
  functionName: string
): Promise<boolean> {
  const expectedAudience = `https://${LOCATION}-${PROJECT_ID}.cloudfunctions.net/${functionName}`;

  // エミュレータでは認証スキップ（開発時のみ）
  if (IS_EMULATOR) {
    console.log(`[DEV] Skipping auth for ${functionName}`);
    return true;
  }

  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    console.error(`[Auth] ${functionName}: No Bearer token found`);
    return false;
  }

  const token = authHeader.split("Bearer ")[1];

  const payload = decodeJwtPayload(token);
  if (payload) {
    const tokenAudience = typeof payload.aud === "string" ? payload.aud : null;
    console.log(`[Auth] ${functionName}: Token metadata:`, JSON.stringify({
      hasIssuer: typeof payload.iss === "string",
      hasAudience: tokenAudience !== null,
      hasExpiry: typeof payload.exp === "number",
      audienceMatchesExpected: tokenAudience === expectedAudience,
    }));

    if (tokenAudience !== null && tokenAudience !== expectedAudience) {
      console.error(`[Auth] ${functionName}: AUDIENCE MISMATCH`);
    }
  }

  try {
    await authClient.verifyIdToken({
      idToken: token,
      audience: expectedAudience,
    });
    console.log(`[Auth] ${functionName}: Token verified successfully`);
    return true;
  } catch (error) {
    console.error(`[Auth] ${functionName}: Token verification FAILED:`,
      error instanceof Error ? error.message : "Unknown error"
    );
    return false;
  }
}
