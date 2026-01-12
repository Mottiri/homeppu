import * as admin from "firebase-admin";

/**
 * Firebase Storage の URL からファイルを削除
 * @param url Firebase Storage の URL
 * @returns 削除に成功した場合は true
 */
export async function deleteStorageFileFromUrl(url: string): Promise<boolean> {
  if (!url || !url.includes("firebasestorage.googleapis.com")) {
    return false;
  }

  try {
    const urlObj = new URL(url);
    const pathSegments = urlObj.pathname.split("/o/");
    if (pathSegments.length < 2) {
      console.warn(`Could not extract path from URL: ${url}`);
      return false;
    }

    // クエリパラメータを除去してデコード
    const encodedPath = pathSegments[1].split("?")[0];
    const storagePath = decodeURIComponent(encodedPath);

    console.log(`Deleting storage file: ${storagePath}`);
    await admin.storage().bucket().file(storagePath).delete();
    console.log(`Successfully deleted: ${storagePath}`);
    return true;
  } catch (error) {
    console.warn(`Failed to delete storage file (${url}):`, error);
    return false;
  }
}
