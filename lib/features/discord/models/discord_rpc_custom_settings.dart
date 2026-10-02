class DiscordRpcCustomSettings {
  final String? customApplicationId;
  final String? customAppIconKey;
  final String idleActivity;
  final String idleDetails;
  final bool enableDetailsPresence;
  final bool enablePlayerPresence;
  final bool enableReaderPresence;

  const DiscordRpcCustomSettings({
    this.customApplicationId,
    this.customAppIconKey,
    this.idleActivity = 'Glazing KuroX',
    this.idleDetails = 'Browsing Catalog',
    this.enableDetailsPresence = true,
    this.enablePlayerPresence = true,
    this.enableReaderPresence = true,
  });

  DiscordRpcCustomSettings copyWith({
    String? customApplicationId,
    String? customAppIconKey,
    String? idleActivity,
    String? idleDetails,
    bool? enableDetailsPresence,
    bool? enablePlayerPresence,
    bool? enableReaderPresence,
  }) {
    return DiscordRpcCustomSettings(
      customApplicationId: customApplicationId ?? this.customApplicationId,
      customAppIconKey: customAppIconKey ?? this.customAppIconKey,
      idleActivity: idleActivity ?? this.idleActivity,
      idleDetails: idleDetails ?? this.idleDetails,
      enableDetailsPresence:
          enableDetailsPresence ?? this.enableDetailsPresence,
      enablePlayerPresence: enablePlayerPresence ?? this.enablePlayerPresence,
      enableReaderPresence: enableReaderPresence ?? this.enableReaderPresence,
    );
  }

  Map<String, dynamic> toJson() => {
        'customApplicationId': customApplicationId,
        'customAppIconKey': customAppIconKey,
        'idleActivity': idleActivity,
        'idleDetails': idleDetails,
        'enableDetailsPresence': enableDetailsPresence,
        'enablePlayerPresence': enablePlayerPresence,
        'enableReaderPresence': enableReaderPresence,
      };

  factory DiscordRpcCustomSettings.fromJson(Map<String, dynamic> json) {
    return DiscordRpcCustomSettings(
      customApplicationId: json['customApplicationId'] as String?,
      customAppIconKey: json['customAppIconKey'] as String?,
      idleActivity: json['idleActivity'] as String? ?? 'Glazing KuroX',
      idleDetails: json['idleDetails'] as String? ?? 'Browsing Catalog',
      enableDetailsPresence: json['enableDetailsPresence'] as bool? ?? true,
      enablePlayerPresence: json['enablePlayerPresence'] as bool? ?? true,
      enableReaderPresence: json['enableReaderPresence'] as bool? ?? true,
    );
  }
}
