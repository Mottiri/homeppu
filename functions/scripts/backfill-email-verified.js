/* Backfill emailVerified for existing users (run locally with Admin SDK credentials)
 *
 * Usage:
 *   node functions/scripts/backfill-email-verified.js
 *   node functions/scripts/backfill-email-verified.js 2026-02-04T00:00:00+09:00
 *
 * Behavior:
 *   - Marks emailVerified=true for users created on/before the cutoff timestamp
 *   - Skips already-verified users
 *
 * Auth:
 *   - set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON, or
 *   - run: gcloud auth application-default login
 */

const admin = require("firebase-admin");

if (admin.apps.length === 0) {
  admin.initializeApp();
}

function parseCutoff(arg) {
  if (!arg) return Date.now();
  const ts = Date.parse(arg);
  if (Number.isNaN(ts)) {
    throw new Error(`Invalid cutoff datetime: ${arg}`);
  }
  return ts;
}

async function backfillEmailVerified(cutoffMillis) {
  let verifiedCount = 0;
  let checkedCount = 0;
  let nextPageToken = undefined;

  do {
    const result = await admin.auth().listUsers(1000, nextPageToken);
    nextPageToken = result.pageToken;

    for (const user of result.users) {
      checkedCount++;
      if (user.emailVerified) continue;

      const createdAt = user.metadata.creationTime
        ? new Date(user.metadata.creationTime).getTime()
        : 0;
      if (!createdAt || createdAt > cutoffMillis) continue;

      await admin.auth().updateUser(user.uid, { emailVerified: true });
      verifiedCount++;
    }
  } while (nextPageToken);

  return { checkedCount, verifiedCount };
}

async function main() {
  const cutoffMillis = parseCutoff(process.argv[2]);
  const cutoffDate = new Date(cutoffMillis).toISOString();
  const { checkedCount, verifiedCount } =
    await backfillEmailVerified(cutoffMillis);
  console.log(
    `Backfill complete. checked=${checkedCount} verified=${verifiedCount} cutoff=${cutoffDate}`
  );
}

main().catch((err) => {
  console.error("Backfill failed:", err);
  process.exit(1);
});
