/* eslint-disable no-console */
const admin = require("firebase-admin");

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }

  const db = admin.firestore();
  const snapshot = await db.collection("nameParts").get();

  let updated = 0;
  let skipped = 0;
  let commonToUpdate = 0;
  let epicToUpdate = 0;

  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const rarity = data.rarity;
    let next = rarity;

    if (rarity === "normal") next = "common";
    if (rarity === "super_rare" || rarity === "ultra_rare") next = "epic";

    if (next === "common" && rarity !== next) commonToUpdate++;
    if (next === "epic" && rarity !== next) epicToUpdate++;

    if (!next || next === rarity) {
      skipped++;
      continue;
    }

    batch.update(doc.ref, {
      rarity: next,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updated++;
    batchCount++;

    if (batchCount >= 400) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  console.log(`Migration done. Updated: ${updated}, skipped: ${skipped}`);
  console.log(`- normal -> common: ${commonToUpdate}`);
  console.log(`- super_rare/ultra_rare -> epic: ${epicToUpdate}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
