import { FieldValue } from "./firebase";

type UserData = Record<string, unknown>;

export function buildPublicUserData(data: UserData) {
  return {
    displayName: data.displayName ?? "",
    bio: data.bio ?? null,
    avatarIndex: data.avatarIndex ?? 0,
    postMode: data.postMode ?? "ai",
    isAI: data.isAI ?? false,
    totalPosts: data.totalPosts ?? 0,
    totalPraises: data.totalPraises ?? 0,
    virtue: data.virtue ?? 100,
    headerImageUrl: data.headerImageUrl ?? null,
    headerImageIndex: data.headerImageIndex ?? null,
    headerPrimaryColor: data.headerPrimaryColor ?? null,
    headerSecondaryColor: data.headerSecondaryColor ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}
