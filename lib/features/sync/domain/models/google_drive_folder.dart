class GoogleDriveFolder {
  final String id;
  final String name;
  final String? parentId;
  final DateTime? modifiedTime;

  const GoogleDriveFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.modifiedTime,
  });

  factory GoogleDriveFolder.fromJson(Map<String, dynamic> json) {
    return GoogleDriveFolder(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Folder',
      parentId: (json['parents'] as List<dynamic>?)?.firstOrNull as String?,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'] as String)
          : null,
    );
  }
}
