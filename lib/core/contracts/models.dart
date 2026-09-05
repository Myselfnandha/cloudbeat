enum AudioQuality {
  flac24Bit,     // 24-bit Hi-Res up to 192kHz (Qobuz / Amazon)
  flac16Bit,     // 16-bit / 44.1kHz Lossless (Deezer / Tidal)
  opus320k,      // 320kbps High-Bitrate Stream
  lossyFallback, // YTMusic Opus/AAC
}

enum PlaybackStatus {
  idle,
  buffering,
  playing,
  paused,
  completed,
  error,
}

enum RepeatMode {
  off,
  all,
  one,
}

enum VaultAuthState {
  unauthenticated,
  waitPhoneNumber,
  waitCode,
  waitPassword,
  authenticated,
  error,
}

class Track {
  final String id;
  final String title;
  final List<String> artists;
  final String album;
  final String? albumArtUrl;
  final int durationSeconds;
  final int? year;
  final String? genre;
  final String? isrc;

  // Telegram Cloud Storage References
  final int? telegramChatId;
  final int? telegramMessageId;
  final String? flacFileId;
  final String? opusFileId;

  final AudioQuality quality;
  final bool isOfflinePinned;
  final DateTime addedAt;

  const Track({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    this.albumArtUrl,
    required this.durationSeconds,
    this.year,
    this.genre,
    this.isrc,
    this.telegramChatId,
    this.telegramMessageId,
    this.flacFileId,
    this.opusFileId,
    this.quality = AudioQuality.flac16Bit,
    this.isOfflinePinned = false,
    required this.addedAt,
  });

  Track copyWith({
    String? id,
    String? title,
    List<String>? artists,
    String? album,
    String? albumArtUrl,
    int? durationSeconds,
    int? year,
    String? genre,
    String? isrc,
    int? telegramChatId,
    int? telegramMessageId,
    String? flacFileId,
    String? opusFileId,
    AudioQuality? quality,
    bool? isOfflinePinned,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      isrc: isrc ?? this.isrc,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      telegramMessageId: telegramMessageId ?? this.telegramMessageId,
      flacFileId: flacFileId ?? this.flacFileId,
      opusFileId: opusFileId ?? this.opusFileId,
      quality: quality ?? this.quality,
      isOfflinePinned: isOfflinePinned ?? this.isOfflinePinned,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artists': artists.join(', '),
      'album': album,
      'album_art_url': albumArtUrl,
      'duration_seconds': durationSeconds,
      'year': year,
      'genre': genre,
      'isrc': isrc,
      'telegram_chat_id': telegramChatId,
      'telegram_message_id': telegramMessageId,
      'flac_file_id': flacFileId,
      'opus_file_id': opusFileId,
      'quality': quality.name,
      'is_offline_pinned': isOfflinePinned ? 1 : 0,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      title: map['title'] as String,
      artists: (map['artists'] as String?)?.split(', ').map((e) => e.trim()).toList() ?? [],
      album: map['album'] as String,
      albumArtUrl: map['album_art_url'] as String?,
      durationSeconds: map['duration_seconds'] as int,
      year: map['year'] as int?,
      genre: map['genre'] as String?,
      isrc: map['isrc'] as String?,
      telegramChatId: map['telegram_chat_id'] as int?,
      telegramMessageId: map['telegram_message_id'] as int?,
      flacFileId: map['flac_file_id'] as String?,
      opusFileId: map['opus_file_id'] as String?,
      quality: AudioQuality.values.firstWhere(
        (e) => e.name == map['quality'],
        orElse: () => AudioQuality.flac16Bit,
      ),
      isOfflinePinned: (map['is_offline_pinned'] as int?) == 1,
      addedAt: map['added_at'] != null ? DateTime.parse(map['added_at'] as String) : DateTime.now(),
    );
  }
}

class UploadJob {
  final String id;
  final String trackId;
  final String localFilePath;
  final String metadataJson;
  final int attempts;
  final String status; // 'pending', 'processing', 'failed', 'completed'

  const UploadJob({
    required this.id,
    required this.trackId,
    required this.localFilePath,
    required this.metadataJson,
    this.attempts = 0,
    this.status = 'pending',
  });

  UploadJob copyWith({
    String? id,
    String? trackId,
    String? localFilePath,
    String? metadataJson,
    int? attempts,
    String? status,
  }) {
    return UploadJob(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      localFilePath: localFilePath ?? this.localFilePath,
      metadataJson: metadataJson ?? this.metadataJson,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'track_id': trackId,
      'local_file_path': localFilePath,
      'metadata_json': metadataJson,
      'attempts': attempts,
      'status': status,
    };
  }

  factory UploadJob.fromMap(Map<String, dynamic> map) {
    return UploadJob(
      id: map['id'] as String,
      trackId: map['track_id'] as String,
      localFilePath: map['local_file_path'] as String,
      metadataJson: map['metadata_json'] as String,
      attempts: map['attempts'] as int,
      status: map['status'] as String,
    );
  }
}
