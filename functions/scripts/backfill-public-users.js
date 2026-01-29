/* Backfill users -> publicUsers (run locally with Admin SDK credentials)
 *
 * Usage:
 *   node functions/scripts/backfill-public-users.js 500
 *
 * Auth:
 *   - set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON, or
 *   - run: gcloud auth application-default login
 */

const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const FieldPath = admin.firestore.FieldPath;
const FieldValue = admin.firestore.FieldValue;

function buildPublicUserData(data) {
  return {
    displayName: data.displayName || "",
    bio: data.bio || null,
    avatarIndex: data.avatarIndex || 0,
    postMode: data.postMode || "ai",
    isAI: data.isAI || false,
    totalPosts: data.totalPosts || 0,
    totalPraises: data.totalPraises || 0,
    virtue: data.virtue || 100,
    headerImageUrl: data.headerImageUrl || null,
    headerImageIndex: data.headerImageIndex || null,
    headerPrimaryColor: data.headerPrimaryColor || null,
    headerSecondaryColor: data.headerSecondaryColor || null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function backfillPublicUsers(pageSize) {
  let lastDoc = null;
  let totalUpdated = 0;

  while (true) {
    let query = db
      .collection("users")
      .orderBy(FieldPath.documentId())
      .limit(pageSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      const publicData = buildPublicUserData(doc.data());
      batch.set(db.collection("publicUsers").doc(doc.id), publicData, {
        merge: true,
      });
    });

    await batch.commit();
    totalUpdated += snapshot.size;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    if (snapshot.size < pageSize) break;
  }

  return totalUpdated;
}

async function main() {
  const rawPageSize = Number(process.argv[2] || "500");
  const pageSize = Math.min(Math.max(rawPageSize, 1), 500);

  const total = await backfillPublicUsers(pageSize);
  console.log(`Backfill complete. Updated ${total} users.`);
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
