/// Firebase service — wraps Auth, Firestore, and Cloud Functions.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:arcbench_mobile/models/terminal.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ── Auth ──────────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  bool get isAuthenticated => _auth.currentUser != null;
  String? get uid => _auth.currentUser?.uid;
  String? get email => _auth.currentUser?.email;
  String? get displayName => _auth.currentUser?.displayName;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (displayName != null && displayName.isNotEmpty) {
      await credential.user?.updateDisplayName(displayName);
    }
    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ── Firestore: Terminals ──────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _terminalsRef =>
      _firestore.collection('terminals');

  Future<List<TerminalInfo>> listTerminals() async {
    if (uid == null) return [];

    final snapshot = await _terminalsRef
        .where('userId', isEqualTo: uid)
        .orderBy('lastActive', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return TerminalInfo.fromJson({
        'id': doc.id,
        ...data,
        'created_at': (data['createdAt'] as Timestamp?)
                ?.toDate()
                .toIso8601String() ??
            DateTime.now().toIso8601String(),
        'last_active': (data['lastActive'] as Timestamp?)
                ?.toDate()
                .toIso8601String() ??
            DateTime.now().toIso8601String(),
        'is_alive': data['isAlive'] ?? true,
        'working_dir': data['workingDir'] ?? '~',
      });
    }).toList();
  }

  Future<String> createTerminal({
    String workingDir = '~',
    String mode = 'shell',
  }) async {
    final doc = await _terminalsRef.add({
      'userId': uid,
      'workingDir': workingDir,
      'mode': mode,
      'command': null,
      'isAlive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> destroyTerminal(String terminalId) async {
    await _terminalsRef.doc(terminalId).update({
      'isAlive': false,
      'destroyedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteTerminal(String terminalId) async {
    await _terminalsRef.doc(terminalId).delete();
  }

  Future<void> updateTerminalActivity(String terminalId) async {
    await _terminalsRef.doc(terminalId).update({
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  /// Real-time stream of user's terminals.
  Stream<List<TerminalInfo>> terminalsStream() {
    if (uid == null) return Stream.value([]);

    return _terminalsRef
        .where('userId', isEqualTo: uid)
        .orderBy('lastActive', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return TerminalInfo.fromJson({
                'id': doc.id,
                ...data,
                'created_at': (data['createdAt'] as Timestamp?)
                        ?.toDate()
                        .toIso8601String() ??
                    DateTime.now().toIso8601String(),
                'last_active': (data['lastActive'] as Timestamp?)
                        ?.toDate()
                        .toIso8601String() ??
                    DateTime.now().toIso8601String(),
                'is_alive': data['isAlive'] ?? true,
                'working_dir': data['workingDir'] ?? '~',
              });
            }).toList());
  }

  // ── Firestore: Sessions (saved terminal history) ──────────────

  Future<void> saveSession({
    required String terminalId,
    required String name,
    required List<Map<String, dynamic>> output,
  }) async {
    await _firestore.collection('sessions').add({
      'userId': uid,
      'terminalId': terminalId,
      'name': name,
      'output': output,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    if (uid == null) return [];

    final snapshot = await _firestore
        .collection('sessions')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs
        .map((doc) => {'id': doc.id, ...doc.data()})
        .toList();
  }

  // ── Firestore: User Settings ──────────────────────────────────

  Future<void> syncSettings(Map<String, dynamic> settings) async {
    if (uid == null) return;
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .set(settings, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> getCloudSettings() async {
    if (uid == null) return {};
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('preferences')
        .get();
    return doc.exists ? doc.data() ?? {} : {};
  }

  // ── Firestore: User Profile ───────────────────────────────────

  Future<Map<String, dynamic>?> getUserProfile() async {
    if (uid == null) return null;
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> updateLastLogin() async {
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).set({
      'lastLogin': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Cloud Functions (callable) ────────────────────────────────

  Future<Map<String, dynamic>> callFunction(
    String name,
    Map<String, dynamic> data,
  ) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<Map<String, dynamic>> getServerStatus() async {
    return callFunction('getStatus', {});
  }
}
