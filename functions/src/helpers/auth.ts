import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { ErrorMessages } from "./errors";
import { isAdmin } from "./admin";

/**
 * Require authenticated user and return uid.
 */
export function requireAuth(
  request: CallableRequest,
  message: string = ErrorMessages.UNAUTHENTICATED
): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", message);
  }

  return request.auth.uid;
}

/**
 * Require admin user and return uid.
 */
export async function requireAdmin(request: CallableRequest): Promise<string> {
  const uid = requireAuth(request);
  const adminStatus = await isAdmin(uid);
  if (!adminStatus) {
    throw new HttpsError("permission-denied", ErrorMessages.ADMIN_REQUIRED);
  }

  return uid;
}
