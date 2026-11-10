import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/body_profile.dart';

abstract interface class BodyProfileStore {
  Future<BodyProfileCollection> load();
  Future<void> save(BodyProfileCollection collection);
}

/// One account/session view of Firestore, shared by all tabs and camera routes.
/// Publishes only acknowledged writes; a failed write never changes selection.
class SessionBodyProfileStore extends ChangeNotifier
    implements BodyProfileStore {
  SessionBodyProfileStore(this.delegate);

  final BodyProfileStore delegate;
  BodyProfileCollection? _value;
  BodyProfileCollection? get value => _value;

  /// Reconcile a completed save reported by a screen using the delegate.
  void acceptSavedCollection(BodyProfileCollection collection) {
    _value = collection;
  }

  Future<BodyProfileCollection>? _read;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  @override
  Future<BodyProfileCollection> load() {
    final value = _value;
    if (value != null) return Future.value(value);
    return _read ??= _load();
  }

  Future<BodyProfileCollection> _load() async {
    try {
      final result = await delegate.load();
      // A write completed while this initial read was in flight.
      return _value ??= result;
    } finally {
      _read = null;
    }
  }

  @override
  Future<void> save(BodyProfileCollection collection) {
    final write = _writes.then((_) async {
      await delegate.save(collection);
      _value = collection;
      if (!_disposed) notifyListeners();
    });
    _writes = write.catchError((Object _) {});
    return write;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SharedPreferencesBodyProfileStore implements BodyProfileStore {
  SharedPreferencesBodyProfileStore(String userId)
    : _key = 'body_profiles_v1_$userId';

  final String _key;

  @override
  Future<BodyProfileCollection> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return const BodyProfileCollection();
    try {
      return BodyProfileCollection.fromJson(jsonDecode(raw));
    } on FormatException {
      return const BodyProfileCollection();
    }
  }

  @override
  Future<void> save(BodyProfileCollection collection) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key,
      jsonEncode(collection.toJson()),
    );
    if (!saved) throw StateError('Không thể lưu hồ sơ trên thiết bị.');
  }
}

/// Only the profile field is read/written; other account data stays untouched.
abstract interface class BodyProfileRemote {
  Future<Object?> loadProfiles();
  Future<void> saveProfiles(Map<String, Object?> profiles);
}

class FirestoreBodyProfileRemote implements BodyProfileRemote {
  FirestoreBodyProfileRemote(String userId, {FirebaseFirestore? firestore})
    : _document = (firestore ?? FirebaseFirestore.instance)
          .collection('users')
          .doc(userId);

  final DocumentReference<Map<String, dynamic>> _document;

  @override
  Future<Object?> loadProfiles() async {
    final snapshot = await _document.get();
    return snapshot.data()?['bodyProfiles'];
  }

  @override
  Future<void> saveProfiles(Map<String, Object?> profiles) =>
      _document.set(<String, Object?>{
        'bodyProfiles': profiles,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}

class FirestoreBodyProfileStore implements BodyProfileStore {
  FirestoreBodyProfileStore(
    String userId, {
    BodyProfileRemote? remote,
    BodyProfileStore? legacyStore,
  }) : _remote = remote ?? FirestoreBodyProfileRemote(userId),
       _legacyStore = legacyStore ?? SharedPreferencesBodyProfileStore(userId);

  final BodyProfileRemote _remote;
  final BodyProfileStore _legacyStore;

  @override
  Future<BodyProfileCollection> load() async {
    final cloudProfiles = await _remote.loadProfiles();
    if (cloudProfiles != null) {
      return BodyProfileCollection.fromJson(cloudProfiles);
    }

    // One-time upgrade from the previous on-device store. A saved empty cloud
    // collection is authoritative and must never resurrect old local profiles.
    final legacyProfiles = await _legacyStore.load();
    if (legacyProfiles.profiles.isNotEmpty) {
      await save(legacyProfiles);
      return legacyProfiles;
    }
    return const BodyProfileCollection();
  }

  @override
  Future<void> save(BodyProfileCollection collection) =>
      _remote.saveProfiles(collection.toJson());
}
