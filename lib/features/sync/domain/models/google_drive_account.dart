import 'dart:convert';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';

class GoogleDriveAccount {
  final String email;
  final String displayName;
  final String photoUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime? tokenExpiry;
  final String selectedFolderId;
  final String selectedFolderName;
  final String customClientId;
  final String customClientSecret;
  final bool autoSyncEnabled;
  final AutoSyncInterval autoSyncInterval;
  final DateTime? lastSyncTimestamp;
  final String? lastSyncStatus;

  const GoogleDriveAccount({
    this.email = '',
    this.displayName = '',
    this.photoUrl = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.tokenExpiry,
    this.selectedFolderId = '',
    this.selectedFolderName = 'KuroX_Backups',
    this.customClientId = '',
    this.customClientSecret = '',
    this.autoSyncEnabled = true,
    this.autoSyncInterval = AutoSyncInterval.onAppStart,
    this.lastSyncTimestamp,
    this.lastSyncStatus,
  });

  bool get isSignedIn =>
      accessToken.isNotEmpty || refreshToken.isNotEmpty || email.isNotEmpty;

  bool get isTokenExpired {
    if (tokenExpiry == null) return false;
    return DateTime.now().isAfter(tokenExpiry!.subtract(const Duration(minutes: 5)));
  }

  GoogleDriveAccount copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiry,
    String? selectedFolderId,
    String? selectedFolderName,
    String? customClientId,
    String? customClientSecret,
    bool? autoSyncEnabled,
    AutoSyncInterval? autoSyncInterval,
    DateTime? lastSyncTimestamp,
    String? lastSyncStatus,
  }) {
    return GoogleDriveAccount(
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiry: tokenExpiry ?? this.tokenExpiry,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      selectedFolderName: selectedFolderName ?? this.selectedFolderName,
      customClientId: customClientId ?? this.customClientId,
      customClientSecret: customClientSecret ?? this.customClientSecret,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      autoSyncInterval: autoSyncInterval ?? this.autoSyncInterval,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
      lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenExpiry': tokenExpiry?.toIso8601String(),
      'selectedFolderId': selectedFolderId,
      'selectedFolderName': selectedFolderName,
      'customClientId': customClientId,
      'customClientSecret': customClientSecret,
      'autoSyncEnabled': autoSyncEnabled,
      'autoSyncInterval': autoSyncInterval.name,
      'lastSyncTimestamp': lastSyncTimestamp?.toIso8601String(),
      'lastSyncStatus': lastSyncStatus,
    };
  }

  factory GoogleDriveAccount.fromMap(Map<String, dynamic> map) {
    return GoogleDriveAccount(
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      accessToken: map['accessToken'] as String? ?? '',
      refreshToken: map['refreshToken'] as String? ?? '',
      tokenExpiry: map['tokenExpiry'] != null
          ? DateTime.tryParse(map['tokenExpiry'] as String)
          : null,
      selectedFolderId: map['selectedFolderId'] as String? ?? '',
      selectedFolderName:
          map['selectedFolderName'] as String? ?? 'KuroX_Backups',
      customClientId: map['customClientId'] as String? ?? '',
      customClientSecret: map['customClientSecret'] as String? ?? '',
      autoSyncEnabled: map['autoSyncEnabled'] as bool? ?? true,
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

  factory GoogleDriveAccount.fromJson(String source) =>
      GoogleDriveAccount.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
