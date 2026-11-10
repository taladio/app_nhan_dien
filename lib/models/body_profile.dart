enum BodyGender {
  unspecified('Chưa chọn'),
  male('Nam'),
  female('Nữ'),
  other('Khác'),
  preferNotToSay('Không muốn trả lời');

  const BodyGender(this.label);
  final String label;

  String? get adviceValue => switch (this) {
    BodyGender.male => 'male',
    BodyGender.female => 'female',
    BodyGender.other => 'other',
    BodyGender.unspecified || BodyGender.preferNotToSay => null,
  };
}

class BodyProfile {
  const BodyProfile({
    required this.id,
    required this.name,
    required this.heightCm,
    required this.weightKg,
    this.gender = BodyGender.unspecified,
  });

  final String id;
  final String name;
  final double heightCm;
  final double weightKg;
  final BodyGender gender;

  BodyProfile copyWith({
    String? name,
    double? heightCm,
    double? weightKg,
    BodyGender? gender,
  }) => BodyProfile(
    id: id,
    name: name ?? this.name,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    gender: gender ?? this.gender,
  );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'gender': gender.name,
  };

  static BodyProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final height = value['heightCm'];
    final weight = value['weightKg'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        height is! num ||
        weight is! num ||
        !height.isFinite ||
        !weight.isFinite ||
        height <= 0 ||
        height > 300 ||
        weight <= 0 ||
        weight > 500) {
      return null;
    }
    return BodyProfile(
      id: id,
      name: name.trim(),
      heightCm: height.toDouble(),
      weightKg: weight.toDouble(),
      gender: BodyGender.values.firstWhere(
        (option) => option.name == value['gender'],
        orElse: () => BodyGender.unspecified,
      ),
    );
  }
}

class BodyProfileCollection {
  const BodyProfileCollection({
    this.profiles = const <BodyProfile>[],
    this.selectedId,
  });

  final List<BodyProfile> profiles;
  final String? selectedId;

  BodyProfile? get selected {
    for (final profile in profiles) {
      if (profile.id == selectedId) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  BodyProfileCollection select(String id) => BodyProfileCollection(
    profiles: profiles,
    selectedId: profiles.any((profile) => profile.id == id) ? id : selectedId,
  );

  BodyProfileCollection upsert(BodyProfile profile) {
    final updated = <BodyProfile>[
      for (final existing in profiles)
        if (existing.id == profile.id) profile else existing,
    ];
    if (!profiles.any((existing) => existing.id == profile.id)) {
      updated.add(profile);
    }
    return BodyProfileCollection(
      profiles: updated,
      selectedId: selectedId ?? profile.id,
    );
  }

  BodyProfileCollection remove(String id) {
    final updated = profiles.where((profile) => profile.id != id).toList();
    return BodyProfileCollection(
      profiles: updated,
      selectedId: selectedId == id
          ? (updated.isEmpty ? null : updated.first.id)
          : selectedId,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'selectedId': selectedId,
  };

  static BodyProfileCollection fromJson(Object? value) {
    if (value is! Map) return const BodyProfileCollection();
    final rawProfiles = value['profiles'];
    final profiles = rawProfiles is List
        ? rawProfiles
              .map(BodyProfile.fromJson)
              .whereType<BodyProfile>()
              .toList()
        : <BodyProfile>[];
    final selectedId = value['selectedId'];
    return BodyProfileCollection(
      profiles: profiles,
      selectedId: selectedId is String ? selectedId : null,
    );
  }
}
