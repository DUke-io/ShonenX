class GoogleDriveFile {
  final String id;
  final String name;
  final int size;
  final DateTime? modifiedTime;
  final String? mimeType;
  final String? description;

  const GoogleDriveFile({
    required this.id,
    required this.name,
    this.size = 0,
    this.modifiedTime,
    this.mimeType,
    this.description,
  });

  String get formattedSize {
    if (size <= 0) return '0 B';
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (size >= 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }

  factory GoogleDriveFile.fromJson(Map<String, dynamic> json) {
    return GoogleDriveFile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'backup.json',
      size: int.tryParse(json['size']?.toString() ?? '0') ?? 0,
      modifiedTime: json['modifiedTime'] != null
          ? DateTime.tryParse(json['modifiedTime'] as String)
          : null,
      mimeType: json['mimeType'] as String?,
      description: json['description'] as String?,
    );
  }
}
