/// Placeholder for the unpublished listening enhancement module. The real
/// implementation is not part of any published tag; this keeps the playback
/// pipeline compiling and inert.
class ListeningEnhancementPreference {
  const ListeningEnhancementPreference();

  factory ListeningEnhancementPreference.fromJson(Object? json) =>
      const ListeningEnhancementPreference();

  Map<String, Object?> toJson() => const <String, Object?>{};
}

class ListeningEnhancement {
  ListeningEnhancement();

  ListeningEnhancementPreference _preference =
      const ListeningEnhancementPreference();

  ListeningEnhancementPreference get preference => _preference;

  Future<void> configure(
    ListeningEnhancementPreference value, {
    int? audioSessionId,
  }) async {
    _preference = value;
  }

  Future<void> setPreference(ListeningEnhancementPreference value) async {
    _preference = value;
  }

  Future<void> dispose() async {}
}