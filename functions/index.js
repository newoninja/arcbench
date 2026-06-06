const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { beforeUserCreated } = require("firebase-functions/v2/identity");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

initializeApp();
const db = getFirestore();

// ─── Auth Triggers ───────────────────────────────────────────────

// Create user profile document when a new user signs up
exports.onUserCreated = beforeUserCreated((event) => {
  const user = event.data;
  return db.collection("users").doc(user.uid).set({
    email: user.email || null,
    displayName: user.displayName || null,
    createdAt: FieldValue.serverTimestamp(),
    lastLogin: FieldValue.serverTimestamp(),
    terminalCount: 0,
  });
});

// ─── Terminal Management ─────────────────────────────────────────

// Create a new terminal session
exports.createTerminal = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const uid = request.auth.uid;
  const { workingDir, mode } = request.data;

  const terminalRef = db.collection("terminals").doc();
  const now = FieldValue.serverTimestamp();

  await terminalRef.set({
    userId: uid,
    workingDir: workingDir || "~",
    mode: mode || "shell",
    command: null,
    isAlive: true,
    createdAt: now,
    lastActive: now,
  });

  // Increment user's terminal count
  await db.collection("users").doc(uid).update({
    terminalCount: FieldValue.increment(1),
  });

  return { terminalId: terminalRef.id };
});

// List user's terminals
exports.listTerminals = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const snapshot = await db
    .collection("terminals")
    .where("userId", "==", request.auth.uid)
    .orderBy("lastActive", "desc")
    .get();

  return {
    terminals: snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate()?.toISOString() || null,
      lastActive: doc.data().lastActive?.toDate()?.toISOString() || null,
    })),
  };
});

// Destroy a terminal
exports.destroyTerminal = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const { terminalId } = request.data;
  if (!terminalId) {
    throw new HttpsError("invalid-argument", "terminalId is required.");
  }

  const terminalRef = db.collection("terminals").doc(terminalId);
  const doc = await terminalRef.get();

  if (!doc.exists) {
    throw new HttpsError("not-found", "Terminal not found.");
  }
  if (doc.data().userId !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Not your terminal.");
  }

  await terminalRef.update({
    isAlive: false,
    destroyedAt: FieldValue.serverTimestamp(),
  });

  await db.collection("users").doc(request.auth.uid).update({
    terminalCount: FieldValue.increment(-1),
  });

  return { success: true };
});

// ─── Session History ─────────────────────────────────────────────

// Save a session (terminal I/O history)
exports.saveSession = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const { terminalId, name, output } = request.data;

  const sessionRef = db.collection("sessions").doc();
  await sessionRef.set({
    userId: request.auth.uid,
    terminalId: terminalId || null,
    name: name || "Untitled Session",
    output: output || [],
    createdAt: FieldValue.serverTimestamp(),
  });

  return { sessionId: sessionRef.id };
});

// List user's sessions
exports.listSessions = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const snapshot = await db
    .collection("sessions")
    .where("userId", "==", request.auth.uid)
    .orderBy("createdAt", "desc")
    .limit(50)
    .get();

  return {
    sessions: snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
      createdAt: doc.data().createdAt?.toDate()?.toISOString() || null,
    })),
  };
});

// ─── User Settings ───────────────────────────────────────────────

// Sync user settings to Firestore
exports.syncSettings = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const { settings } = request.data;
  if (!settings) {
    throw new HttpsError("invalid-argument", "settings object is required.");
  }

  await db
    .collection("users")
    .doc(request.auth.uid)
    .collection("settings")
    .doc("preferences")
    .set(settings, { merge: true });

  return { success: true };
});

// Get user settings
exports.getSettings = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const doc = await db
    .collection("users")
    .doc(request.auth.uid)
    .collection("settings")
    .doc("preferences")
    .get();

  return { settings: doc.exists ? doc.data() : {} };
});

// ─── Server Status ───────────────────────────────────────────────

exports.getStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const userDoc = await db.collection("users").doc(request.auth.uid).get();

  return {
    status: "online",
    version: "2.0.0",
    backend: "firebase",
    user: userDoc.exists ? userDoc.data() : null,
  };
});
