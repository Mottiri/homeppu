import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";

import { db } from "../helpers/firebase";
import { LOCATION } from "../config/constants";
import { buildPublicUserData } from "../helpers/public-users";

export const onUserCreated = onDocumentCreated(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const userId = event.params.userId;
    const data = snap.data() as Record<string, unknown>;
    const publicData = buildPublicUserData(data);

    await db.collection("publicUsers").doc(userId).set(publicData, { merge: true });
  }
);

export const onUserUpdated = onDocumentUpdated(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const snap = event.data?.after;
    if (!snap) return;

    const userId = event.params.userId;
    const data = snap.data() as Record<string, unknown>;
    const publicData = buildPublicUserData(data);

    await db.collection("publicUsers").doc(userId).set(publicData, { merge: true });
  }
);

export const onUserDeleted = onDocumentDeleted(
  {
    document: "users/{userId}",
    region: LOCATION,
  },
  async (event) => {
    const userId = event.params.userId;
    await db.collection("publicUsers").doc(userId).delete();
  }
);
