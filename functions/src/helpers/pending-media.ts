import { db } from "./firebase";
import { extractStoragePathFromUrl } from "./storage";
import { MediaItem } from "../types";

export function getPendingMediaDocId(storagePath: string): string {
  return encodeURIComponent(storagePath);
}

export function getMediaStoragePath(item: Pick<MediaItem, "url" | "storagePath">): string | null {
  if (item.storagePath) {
    return item.storagePath;
  }
  return extractStoragePathFromUrl(item.url);
}

export function getMediaStoragePaths(mediaItems: MediaItem[]): string[] {
  return mediaItems
      .map((item) => getMediaStoragePath(item))
      .filter((storagePath): storagePath is string => Boolean(storagePath));
}

export async function deletePendingMediaByStoragePath(storagePath: string): Promise<void> {
  if (!storagePath) {
    return;
  }

  try {
    await db.collection("pendingMedia").doc(getPendingMediaDocId(storagePath)).delete();
  } catch (error) {
    console.warn(`Failed to delete pendingMedia doc for ${storagePath}:`, error);
  }
}

export async function deletePendingMediaByStoragePaths(storagePaths: string[]): Promise<void> {
  await Promise.all(
    [...new Set(storagePaths)]
      .filter((storagePath) => Boolean(storagePath))
      .map((storagePath) => deletePendingMediaByStoragePath(storagePath))
  );
}
