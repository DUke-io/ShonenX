import '../../javascript/http.dart';

class Video {
  String url;
  String quality;
  String originalUrl;
  Map<String, String>? headers;
  List<Track>? subtitles;
  List<Track>? audios;

  Video(
    this.url,
    this.quality,
    this.originalUrl, {
    this.headers,
    this.subtitles,
    this.audios,
  });

  factory Video.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString().trim() ?? '';
    final quality = json['quality']?.toString().trim() ??
        json['title']?.toString().trim() ??
        'Default';
    final originalUrl = json['originalUrl']?.toString().trim();

    return Video(
      url,
      quality,
      (originalUrl != null && originalUrl.isNotEmpty) ? originalUrl : url,
      headers: (json['headers'] as Map?)?.toMapStringString,
      subtitles: json['subtitles'] != null
          ? (json['subtitles'] as List)
              .where((e) => e is Map)
              .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
      audios: json['audios'] != null
          ? (json['audios'] as List)
              .where((e) => e is Map)
              .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'quality': quality,
        'originalUrl': originalUrl,
        'headers': headers,
        'subtitles': subtitles?.map((e) => e.toJson()).toList(),
        'audios': audios?.map((e) => e.toJson()).toList(),
      };
}

class Track {
  String? file;
  String? label;

  Track({this.file, this.label});

  Track.fromJson(Map<String, dynamic> json) {
    file = json['file']?.toString().trim();
    label = json['label']?.toString().trim();
  }

  Map<String, dynamic> toJson() => {'file': file, 'label': label};
}
