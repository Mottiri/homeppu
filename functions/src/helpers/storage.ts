import * as admin from "firebase-admin";

export function extractStoragePathFromUrl(url: string): string | null {
  if (!url || !url.includes("firebasestorage.googleapis.com")) {
    return null;
  }

  try {
    const urlObj = new URL(url);
    const pathSegments = urlObj.pathname.split("/o/");
    if (pathSegments.length < 2) {
      return null;
    }

    const encodedPath = pathSegments[1].split("?")[0];
    return decodeURIComponent(encodedPath);
  } catch (error) {
    console.warn(`Failed to parse storage url: ${url}`, error);
    return null;
  }
}

export async function deleteStorageFileByPath(storagePath: string): Promise<boolean> {
  if (!storagePath) {
    return false;
  }

  try {
    console.log(`Deleting storage file: ${storagePath}`);
    await admin.storage().bucket().file(storagePath).delete();
    console.log(`Successfully deleted: ${storagePath}`);
    return true;
  } catch (error: any) {
    const errorCode = error?.code ?? error?.errors?.[0]?.reason;
    if (errorCode === 404 || errorCode === "notFound") {
      console.log(`Storage file already removed: ${storagePath}`);
      return false;
    }
    console.warn(`Failed to delete storage file (${storagePath}):`, error);
    return false;
  }
}

export async function deleteStorageFileFromUrl(url: string): Promise<boolean> {
  const storagePath = extractStoragePathFromUrl(url);
  if (!storagePath) {
    return false;
  }

  return deleteStorageFileByPath(storagePath);
}
