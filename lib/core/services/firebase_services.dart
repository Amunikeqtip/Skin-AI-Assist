import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class FirebaseSetup {
  static const _apiKey =
      String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _messagingSenderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID');
  static const _androidAppId =
      String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosAppId =
      String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId =
      String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _authDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get hasConfiguration =>
      _apiKey.isNotEmpty &&
      _projectId.isNotEmpty &&
      _messagingSenderId.isNotEmpty &&
      _appIdForPlatform.isNotEmpty;

  static String get _appIdForPlatform {
    if (kIsWeb) return _webAppId;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        _iosAppId,
      _ => _androidAppId,
    };
  }

  static Future<bool> initialize() async {
    if (Firebase.apps.isNotEmpty) return true;
    if (!hasConfiguration) {
      if (kIsWeb) return false;
      await Firebase.initializeApp();
      return true;
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: _apiKey,
        appId: _appIdForPlatform,
        messagingSenderId: _messagingSenderId,
        projectId: _projectId,
        authDomain:
            _authDomain.isEmpty ? null : _authDomain,
        storageBucket:
            _storageBucket.isEmpty ? null : _storageBucket,
      ),
    );
    return true;
  }
}

class FirebaseAuthService {
  FirebaseAuthService._();

  static final instance = FirebaseAuthService._();
  bool _ready = false;

  bool get isReady => _ready;
  User? get currentUser =>
      _ready ? FirebaseAuth.instance.currentUser : null;
  Stream<User?> get authChanges => _ready
      ? FirebaseAuth.instance.authStateChanges()
      : const Stream<User?>.empty();

  void markReady(bool ready) => _ready = ready;

  Future<void> signIn(String email, String password) async {
    _ensureReady();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordReset(String email) async {
    _ensureReady();
    await FirebaseAuth.instance.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  Future<void> signUp(
      String name, String email, String password) async {
    _ensureReady();
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(name.trim());
    await credential.user?.reload();
    await Hive.box('profile').put('details', {
      'name': name.trim(),
      'age': 'Prefer not to say',
      'gender': 'Prefer not to say',
      'skin': 'Not sure',
    });
    await FirebaseCloudStore.instance
        .syncLocalData()
        .catchError((_) {});
  }

  Future<void> signInDemo() async {
    _ensureReady();
    const email = 'demo@skinai.app';
    const password = 'SkinAI123!';
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found' &&
          error.code != 'invalid-credential') {
        rethrow;
      }
      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
    await FirebaseCloudStore.instance
        .syncLocalData()
        .catchError((_) {});
  }

  Future<void> signOut() async {
    _ensureReady();
    await FirebaseAuth.instance.signOut();
  }

  void _ensureReady() {
    if (!_ready) {
      throw FirebaseAuthException(
        code: 'firebase-not-configured',
        message:
            'Firebase has not been configured for this app yet.',
      );
    }
  }
}

class AuthRouterRefresh extends ChangeNotifier {
  StreamSubscription<User?>? _subscription;

  void start() {
    if (!FirebaseAuthService.instance.isReady ||
        _subscription != null) {
      return;
    }
    _subscription = FirebaseAuthService.instance.authChanges
        .listen((user) {
      if (user != null) {
        unawaited(
          FirebaseCloudStore.instance
              .syncLocalData()
              .catchError((_) {}),
        );
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class FirebaseCloudStore {
  FirebaseCloudStore._();

  static final instance = FirebaseCloudStore._();
  FirebaseFirestore get _firestore =>
      FirebaseFirestore.instance;
  User? get _user =>
      FirebaseAuthService.instance.currentUser;

  DocumentReference<Map<String, dynamic>>?
      get _userDocument {
    final user = _user;
    return user == null
        ? null
        : _firestore.collection('users').doc(user.uid);
  }

  Future<void> syncLocalData() async {
    final userDocument = _userDocument;
    final user = _user;
    if (userDocument == null || user == null) return;

    final preferences = Hive.box('preferences');
    final profile = Hive.box('profile');
    final previousUserId =
        preferences.get('firebase_active_user') as String?;
    if (previousUserId != null &&
        previousUserId != user.uid) {
      await Hive.box('scans').clear();
      await profile.delete('details');
      await preferences.delete('daily_care_routine');
    }
    await preferences.put('firebase_active_user', user.uid);
    final existing = await userDocument.get();
    final cloudData =
        existing.data() ?? <String, dynamic>{};
    final cloudPreferences = cloudData['preferences'];
    if (!profile.containsKey('details') &&
        cloudData['profile'] is Map) {
      await profile.put('details', cloudData['profile']);
    }
    if (cloudPreferences is Map) {
      if (!preferences.containsKey('accepted') &&
          cloudPreferences.containsKey('accepted')) {
        await preferences.put(
            'accepted', cloudPreferences['accepted']);
      }
      if (!preferences.containsKey('daily_care_routine') &&
          cloudPreferences['daily_care_routine'] is Map) {
        await preferences.put(
          'daily_care_routine',
          cloudPreferences['daily_care_routine'],
        );
      }
    }
    await userDocument.set({
      'profile': _safeMap(profile.get('details')),
      'preferences': {
        'accepted': preferences.get('accepted',
            defaultValue: false),
        'daily_care_routine': _safeMap(
          preferences.get('daily_care_routine'),
        ),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final scans = Hive.box('scans');
    final scanCollection = userDocument.collection('scans');
    for (final key in scans.keys) {
      if (key is String && key.startsWith('cloud_')) {
        continue;
      }
      await scanCollection.doc('local_$key').set(
            Map<String, dynamic>.from(
                scans.get(key) as Map),
            SetOptions(merge: true),
          );
    }

    final remoteScans = await scanCollection.get();
    for (final document in remoteScans.docs) {
      final localKey = 'cloud_${document.id}';
      if (!scans.containsKey(localKey)) {
        await scans.put(localKey, document.data());
      }
    }
  }

  Future<void> syncProfile(
      Map<String, dynamic> profile) async {
    await _userDocument?.set({
      'profile': profile,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> syncPreferences(
      Map<String, dynamic> preferences) async {
    await _userDocument?.set({
      'preferences': preferences,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> syncScan(
      String localKey, Map<String, dynamic> scan) async {
    final document = _userDocument;
    if (document == null) return;
    await document
        .collection('scans')
        .doc('local_$localKey')
        .set(scan);
  }

  Future<void> deleteScan(String localKey) async {
    final document = _userDocument;
    if (document == null) return;
    final id = localKey.startsWith('cloud_')
        ? localKey.substring('cloud_'.length)
        : 'local_$localKey';
    await document.collection('scans').doc(id).delete();
  }

  Future<void> clearUserData() async {
    final document = _userDocument;
    if (document == null) return;
    final scans = await document.collection('scans').get();
    final batch = _firestore.batch();
    for (final scan in scans.docs) {
      batch.delete(scan.reference);
    }
    batch.delete(document);
    await batch.commit();
  }

  Map<String, dynamic> _safeMap(dynamic value) =>
      value is Map
          ? value.map(
              (key, item) => MapEntry(key.toString(), item))
          : <String, dynamic>{};
}
