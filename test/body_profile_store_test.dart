import 'dart:async';

import 'package:app_nhan_dien/models/body_profile.dart';
import 'package:app_nhan_dien/services/body_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedProfileStore implements BodyProfileStore {
  final read = Completer<BodyProfileCollection>();
  int reads = 0;
  @override
  Future<BodyProfileCollection> load() {
    reads++;
    return read.future;
  }

  @override
  Future<void> save(BodyProfileCollection collection) async {}
}

class _Remote implements BodyProfileRemote {
  Object? data;
  bool unavailable = false;
  int saves = 0;

  @override
  Future<Object?> loadProfiles() async {
    if (unavailable) throw StateError('Firestore unavailable');
    return data;
  }

  @override
  Future<void> saveProfiles(Map<String, Object?> profiles) async {
    if (unavailable) throw StateError('Firestore unavailable');
    data = profiles;
    saves++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'session shares acknowledged writes and does not publish failures',
    () async {
      final remote = _Remote();
      final store = SessionBodyProfileStore(
        FirestoreBodyProfileStore('a', remote: remote),
      );
      addTearDown(store.dispose);
      var notifications = 0;
      store.addListener(() => notifications++);
      final initial = const BodyProfileCollection().upsert(
        const BodyProfile(
          id: 'a',
          name: 'A',
          heightCm: 170,
          weightKg: 65,
          gender: BodyGender.male,
        ),
      );
      await store.save(initial);
      remote.unavailable = true;
      await expectLater(
        store.save(const BodyProfileCollection()),
        throwsStateError,
      );
      expect((await store.load()).selected?.gender, BodyGender.male);
      expect(notifications, 1);
      remote.unavailable = false;
      await store.save(const BodyProfileCollection());
      expect((await store.load()).profiles, isEmpty);
      expect(notifications, 2);
    },
  );

  test('late initial read cannot overwrite a newer saved profile', () async {
    final remote = _DelayedProfileStore();
    final store = SessionBodyProfileStore(remote);
    addTearDown(store.dispose);
    final first = store.load();
    final second = store.load();
    final saved = const BodyProfileCollection().upsert(
      const BodyProfile(id: 'new', name: 'Mới', heightCm: 170, weightKg: 65),
    );
    await store.save(saved);
    remote.read.complete(const BodyProfileCollection());
    expect((await first).selected?.id, 'new');
    expect((await second).selected?.id, 'new');
    expect(remote.reads, 1);
  });

  test('saves multiple profiles and selection per account', () async {
    final firstStore = SharedPreferencesBodyProfileStore('account-a');
    final secondStore = SharedPreferencesBodyProfileStore('account-b');
    final first = const BodyProfile(
      id: 'first',
      name: 'Ở nhà',
      heightCm: 170,
      weightKg: 65,
    );
    final second = const BodyProfile(
      id: 'second',
      name: 'Đi chơi',
      heightCm: 180,
      weightKg: 75,
    );
    await firstStore.save(
      const BodyProfileCollection()
          .upsert(first)
          .upsert(second)
          .select(second.id),
    );

    final loaded = await firstStore.load();
    expect(loaded.profiles.map((profile) => profile.name), <String>[
      'Ở nhà',
      'Đi chơi',
    ]);
    expect(loaded.selected?.id, second.id);
    expect((await secondStore.load()).profiles, isEmpty);

    await firstStore.save(loaded.upsert(second.copyWith(name: 'Đã đổi tên')));
    expect((await firstStore.load()).selected?.name, 'Đã đổi tên');
    await firstStore.save((await firstStore.load()).remove(second.id));
    expect((await firstStore.load()).selected?.id, first.id);
  });

  test('invalid stored JSON falls back safely', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'body_profiles_v1_account-a': '{broken',
    });
    final loaded = await SharedPreferencesBodyProfileStore('account-a').load();
    expect(loaded.profiles, isEmpty);
  });

  test(
    'Firestore keeps multiple named profiles and selected profile',
    () async {
      final remote = _Remote();
      final store = FirestoreBodyProfileStore('account-a', remote: remote);
      final collection = const BodyProfileCollection()
          .upsert(
            const BodyProfile(
              id: 'a',
              name: 'Cá nhân',
              heightCm: 170,
              weightKg: 65,
              gender: BodyGender.female,
            ),
          )
          .upsert(
            const BodyProfile(
              id: 'b',
              name: 'Bạn bè',
              heightCm: 180,
              weightKg: 75,
            ),
          )
          .select('b');
      await store.save(collection);

      final loaded = await store.load();
      expect(loaded.profiles.map((profile) => profile.name), <String>[
        'Cá nhân',
        'Bạn bè',
      ]);
      expect(loaded.selected?.id, 'b');
      expect(loaded.profiles.first.gender, BodyGender.female);
      expect(loaded.profiles.last.gender, BodyGender.unspecified);
      expect(remote.saves, 1);
    },
  );

  test('migrates old local profiles once when cloud field is absent', () async {
    final legacy = SharedPreferencesBodyProfileStore('account-a');
    await legacy.save(
      const BodyProfileCollection().upsert(
        const BodyProfile(id: 'old', name: 'Cũ', heightCm: 168, weightKg: 62),
      ),
    );
    final remote = _Remote();
    final store = FirestoreBodyProfileStore(
      'account-a',
      remote: remote,
      legacyStore: legacy,
    );

    expect((await store.load()).selected?.name, 'Cũ');
    expect(remote.saves, 1);
    expect((await store.load()).selected?.name, 'Cũ');
    expect(remote.saves, 1);

    await store.save(const BodyProfileCollection());
    expect((await store.load()).profiles, isEmpty);
    expect(remote.saves, 2);
  });

  test('Firestore failures are not disguised as empty local data', () async {
    final remote = _Remote()..unavailable = true;
    final store = FirestoreBodyProfileStore('account-a', remote: remote);
    await expectLater(store.load(), throwsStateError);
    await expectLater(
      store.save(const BodyProfileCollection()),
      throwsStateError,
    );
  });

  test('old cloud profiles without gender remain readable', () {
    final profile = BodyProfile.fromJson(<String, Object>{
      'id': 'old',
      'name': 'Cũ',
      'heightCm': 165,
      'weightKg': 60,
    });
    expect(profile?.gender, BodyGender.unspecified);
  });
}
