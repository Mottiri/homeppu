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
    avatarParts: data.avatarParts || null,
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

function addNamePartVariants(map, id, text) {
  if (!id) return;
  const trimmed = id.trim();
  map.set(id, text);
  map.set(trimmed, text);

  if (trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_pre_", "");
    map.set(`prefix_${base}`, text);
  } else if (trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_suf_", "");
    map.set(`suffix_${base}`, text);
  } else if (trimmed.startsWith("prefix_") && !trimmed.startsWith("prefix_pre_")) {
    const base = trimmed.replace("prefix_", "");
    map.set(`prefix_pre_${base}`, text);
    map.set(`prefix_pre_${base} `, text);
  } else if (trimmed.startsWith("suffix_") && !trimmed.startsWith("suffix_suf_")) {
    const base = trimmed.replace("suffix_", "");
    map.set(`suffix_suf_${base}`, text);
    map.set(`suffix_suf_${base} `, text);
  }
}

async function loadNamePartTexts() {
  const snapshot = await db.collection("nameParts").get();
  const map = new Map();
  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    if (data && typeof data.text === "string") {
      addNamePartVariants(map, doc.id, data.text);
    }
  });
  return map;
}

async function backfillPublicUsers(pageSize) {
  let lastDoc = null;
  let totalUpdated = 0;
  const namePartTexts = await loadNamePartTexts();

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

    const publicBatch = db.batch();
    const userBatch = db.batch();
    let userBatchCount = 0;
    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const prefixId = data.namePrefix;
      const suffixId = data.nameSuffix;
      const prefixText =
        typeof prefixId === "string" ? namePartTexts.get(prefixId) : null;
      const suffixText =
        typeof suffixId === "string" ? namePartTexts.get(suffixId) : null;
      const computedDisplayName =
        prefixText && suffixText
          ? `${prefixText}${suffixText}`
          : data.displayName || "";

      const publicData = buildPublicUserData({
        ...data,
        displayName: computedDisplayName,
      });

      publicBatch.set(db.collection("publicUsers").doc(doc.id), publicData, {
        merge: true,
      });

      if (computedDisplayName && computedDisplayName !== data.displayName) {
        userBatch.update(doc.ref, {
          displayName: computedDisplayName,
          updatedAt: FieldValue.serverTimestamp(),
        });
        userBatchCount++;
      }
    });

    await publicBatch.commit();
    if (userBatchCount > 0) {
      await userBatch.commit();
    }
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
