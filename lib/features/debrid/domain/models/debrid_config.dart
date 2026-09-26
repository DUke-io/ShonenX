import 'dart:convert';

enum DebridProvider {
  realDebrid('Real-Debrid', 'https://api.real-debrid.com/rest/1.0'),
  torbox('Torbox', 'https://api.torbox.app/v1/api'),
  allDebrid('AllDebrid', 'https://api.alldebrid.com/v4');

  final String displayName;
  final String apiBaseUrl;

  const DebridProvider(this.displayName, this.apiBaseUrl);

  static DebridProvider fromString(String? val) {
    return DebridProvider.values.firstWhere(
      (e) => e.name == val,
      orElse: () => DebridProvider.realDebrid,
    );
  }
}

enum PreferredResolution {
  res4k('4K (2160p)', '2160p'),
  res1080p('1080p (FHD)', '1080p'),
  res720p('720p (HD)', '720p'),
  any('Any / Highest Available', '');

  final String label;
  final String queryTag;
  const PreferredResolution(this.label, this.queryTag);

  static PreferredResolution fromString(String? val) {
    return PreferredResolution.values.firstWhere(
      (e) => e.name == val,
      orElse: () => PreferredResolution.res1080p,
    );
  }
}

class DebridConfig {
  final bool isEnabled;
  final DebridProvider provider;
  final String apiKey;
  final PreferredResolution preferredResolution;
  final List<String> preferredGroups;
  final bool autoSelectCached;

  const DebridConfig({
    this.isEnabled = false,
    this.provider = DebridProvider.realDebrid,
    this.apiKey = '',
    this.preferredResolution = PreferredResolution.res1080p,
    this.preferredGroups = const ['SubsPlease', 'Erai-raws', 'Judas', 'Ember'],
    this.autoSelectCached = true,
  });

  DebridConfig copyWith({
    bool? isEnabled,
    DebridProvider? provider,
    String? apiKey,
    PreferredResolution? preferredResolution,
    List<String>? preferredGroups,
    bool? autoSelectCached,
  }) {
    return DebridConfig(
      isEnabled: isEnabled ?? this.isEnabled,
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      preferredResolution: preferredResolution ?? this.preferredResolution,
      preferredGroups: preferredGroups ?? this.preferredGroups,
      autoSelectCached: autoSelectCached ?? this.autoSelectCached,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isEnabled': isEnabled,
      'provider': provider.name,
      'apiKey': apiKey,
      'preferredResolution': preferredResolution.name,
      'preferredGroups': preferredGroups,
      'autoSelectCached': autoSelectCached,
    };
  }

  factory DebridConfig.fromMap(Map<String, dynamic> map) {
    return DebridConfig(
      isEnabled: map['isEnabled'] as bool? ?? false,
      provider: DebridProvider.fromString(map['provider'] as String?),
      apiKey: map['apiKey'] as String? ?? '',
      preferredResolution: PreferredResolution.fromString(
        map['preferredResolution'] as String?,
      ),
      preferredGroups:
          (map['preferredGroups'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['SubsPlease', 'Erai-raws', 'Judas', 'Ember'],
      autoSelectCached: map['autoSelectCached'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DebridConfig.fromJson(String source) =>
      DebridConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class DebridAccountInfo {
  final String username;
  final String email;
  final String type; // 'premium' or 'free'
  final DateTime? expirationDate;
  final int points;

  const DebridAccountInfo({
    required this.username,
    this.email = '',
    required this.type,
    this.expirationDate,
    this.points = 0,
  });

  bool get isPremium => type.toLowerCase() == 'premium';

  int get daysRemaining {
    if (expirationDate == null) return 0;
    final diff = expirationDate!.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }
}
