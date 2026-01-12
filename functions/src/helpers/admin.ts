import * as admin from "firebase-admin";

/**
 * ユーザーが管理者かどうかをCustom Claimsでチェック
 */
export async function isAdmin(uid: string): Promise<boolean> {
  try {
    const user = await admin.auth().getUser(uid);
    return user.customClaims?.admin === true;
  } catch (error) {
    console.error(`Error checking admin status for ${uid}:`, error);
    return false;
  }
}

/**
 * 管理者権限を持つすべてのユーザーのUIDを取得
 */
export async function getAdminUids(): Promise<string[]> {
  const adminUids: string[] = [];
  let pageToken: string | undefined;

  do {
    const listUsersResult = await admin.auth().listUsers(1000, pageToken);

    listUsersResult.users.forEach((userRecord) => {
      if (userRecord.customClaims?.admin === true) {
        adminUids.push(userRecord.uid);
      }
    });

    pageToken = listUsersResult.pageToken;
  } while (pageToken);

  return adminUids;
}
