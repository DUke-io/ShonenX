import 'dart:convert';

enum CloudSyncProviderType {
  disabled('Disabled'),
  webdav('WebDAV (Nextcloud / Oracle Cloud)'),
  githubGist('Private GitHub Gist');

  final String displayName;
  const CloudSyncProviderType(this.displayName);

  static CloudSyncProviderType fromString(String? val) {
    return CloudSyncProviderType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => CloudSyncProviderType.disabled,
    );
  }
}

enum AutoSyncInterval {
  disabled('Disabled'),
  onAppStart('On App Launch'),
  every6Hours('Every 6 Hours'),
  daily('Once Daily');

  final String displayName;
  const AutoSyncInterval(this.displayName);

  static AutoSyncInterval fromString(String? val) {
    return AutoSyncInterval.values.firstWhere(
      (e) => e.name == val,
      orElse: () => AutoSyncInterval.onAppStart,
    );
  }
}

class CloudSyncConfig {
  final CloudSyncProviderType providerType;
  final String webdavUrl;
  final String webdavUsername;
  final String webdavPassword;
  final String webdavFilePath;
  final String gistToken;
  final String gistId;
  final AutoSyncInterval autoSyncInterval;
  final DateTime? lastSyncTimestamp;
  final String? lastSyncStatus;

  const CloudSyncConfig({
    this.providerType = CloudSyncProviderType.disabled,
    this.webdavUrl = '',
    this.webdavUsername = '',
    this.webdavPassword = '',
    this.webdavFilePath = 'kurox_backup.json',
    this.gistToken = '',
    this.gistId = '',
    this.autoSyncInterval = AutoSyncInterval.onAppStart,
    this.lastSyncTimestamp,
    this.lastSyncStatus,
  });

  bool get isConfigured {
    switch (providerType) {
      case CloudSyncProviderType.webdav:
        return webdavUrl.isNotEmpty && webdavUsername.isNotEmpty;
      case CloudSyncProviderType.githubGist:
        return gistToken.isNotEmpty;
      case CloudSyncProviderType.disabled:
        return false;
    }
  }

  CloudSyncConfig copyWith({
    CloudSyncProviderType? providerType,
    String? webdavUrl,
    String? webdavUsername,
    String? webdavPassword,
    String? webdavFilePath,
    String? gistToken,
    String? gistId,
    AutoSyncInterval? autoSyncInterval,
    DateTime? lastSyncTimestamp,
    String? lastSyncStatus,
  }) {
    return CloudSyncConfig(
      providerType: providerType ?? this.providerType,
      webdavUrl: webdavUrl ?? this.webdavUrl,
      webdavUsername: webdavUsername ?? this.webdavUsername,
      webdavPassword: webdavPassword ?? this.webdavPassword,
      webdavFilePath: webdavFilePath ?? this.webdavFilePath,
      gistToken: gistToken ?? this.gistToken,
      gistId: gistId ?? this.gistId,
      autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'providerType': providerType.name,
      'webdavUrl': webdavUrl,
      'webdavUsername': webdavUsername,
      'webdavPassword': webdavPassword,
      'webdavFilePath': webdavFilePath,
      'gistToken': gistToken,
      'gistId': gistId,
      'autoSyncInterval': autoSyncInterval.name,
      'lastSyncTimestamp': lastSyncTimestamp?.toIso8601String(),
      'lastSyncStatus': lastSyncStatus,
    };
  }

  factory CloudSyncConfig.fromMap(Map<String, dynamic> map) {
    return CloudSyncConfig(
      providerType: CloudSyncProviderType.fromString(
        map['providerType'] as String?,
      ),
      webdavUrl: map['webdavUrl'] as String? ?? '',
      webdavUsername: map['webdavUsername'] as String? ?? '',
      webdavPassword: map['webdavPassword'] as String? ?? '',
      webdavFilePath: map['webdavFilePath'] as String? ?? 'kurox_backup.json',
      gistToken: map['gistToken'] as String? ?? '',
      gistId: map['gistId'] as String? ?? '',
      autoSyncInterval: AutoSyncInterval.fromString(
        map['autoSyncInterval'] as String?,
      ),
      lastSyncTimestamp: map['lastSyncTimestamp'] != null
          ? DateTime.tryParse(map['lastSyncTimestamp'] as String)
          : null,
      lastSyncStatus: map['lastSyncStatus'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CloudSyncConfig.fromJson(String source) =>
      CloudSyncConfig.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
