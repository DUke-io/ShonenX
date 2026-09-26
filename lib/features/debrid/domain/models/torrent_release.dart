class TorrentRelease {
  final String title;
  final String magnet;
  final String infoHash;
  final String? torrentUrl;
  final int sizeBytes;
  final int seeders;
  final int leechers;
  final String resolution;
  final String releaseGroup;
  final bool isDualAudio;
  final bool isBatch;
  final String source;
  final bool isCachedOnDebrid;

  const TorrentRelease({
    required this.title,
    required this.magnet,
    required this.infoHash,
    this.torrentUrl,
    this.sizeBytes = 0,
    this.seeders = 0,
    this.leechers = 0,
    this.resolution = '1080p',
    this.releaseGroup = 'Unknown',
    this.isDualAudio = false,
    this.isBatch = false,
    this.source = 'AnimeTosho',
    this.isCachedOnDebrid = false,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return 'Unknown size';
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  TorrentRelease copyWith({
    String? title,
    String? magnet,
    String? infoHash,
    String? torrentUrl,
    int? sizeBytes,
    int? seeders,
    int? leechers,
    String? resolution,
    String? releaseGroup,
    bool? isDualAudio,
    bool? isBatch,
    String? source,
    bool? isCachedOnDebrid,
  }) {
    return TorrentRelease(
      title: title ?? this.title,
      magnet: magnet ?? this.magnet,
      infoHash: infoHash ?? this.infoHash,
      torrentUrl: torrentUrl ?? this.torrentUrl,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      resolution: resolution ?? this.resolution,
      releaseGroup: releaseGroup ?? this.releaseGroup,
      isDualAudio: isDualAudio ?? this.isDualAudio,
      isBatch: isBatch ?? this.isBatch,
      source: source ?? this.source,
      isCachedOnDebrid: isCachedOnDebrid ?? this.isCachedOnDebrid,
    );
  }
}
