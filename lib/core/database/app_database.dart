import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../contracts/catalog_contract.dart';
import '../contracts/models.dart';

class AppDatabase implements CatalogContract {
  static AppDatabase? _instance;
  static Database? _database;
  final String? _customPath;

  AppDatabase._({String? customPath}) : _customPath = customPath;

  static AppDatabase get instance => _instance ??= AppDatabase._();

  static AppDatabase testInstance({required String customPath}) {
    return AppDatabase._(customPath: customPath);
  }

  static void initializeForTesting({Database? db}) {
    _database = db;
    _instance = AppDatabase._();
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase(_customPath);
    return _database!;
  }

  Future<Database> _initDatabase(String? customPath) async {
    if (customPath == inMemoryDatabasePath) {
      return await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    String path;
    if (customPath != null) {
      path = customPath;
    } else if (Platform.isLinux || Platform.isWindows) {
      final appDir = await getApplicationSupportDirectory();
      path = join(appDir.path, 'cloudbeat_catalog.db');
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'cloudbeat_catalog.db');
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE tracks ADD COLUMN is_downloaded INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tracks ADD COLUMN local_file_path TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE tracks ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artists TEXT NOT NULL,
        album TEXT NOT NULL,
        album_art_url TEXT,
        duration_seconds INTEGER NOT NULL,
        year INTEGER,
        genre TEXT,
        isrc TEXT,
        is_downloaded INTEGER NOT NULL DEFAULT 0,
        local_file_path TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        quality TEXT NOT NULL,
        is_offline_pinned INTEGER NOT NULL DEFAULT 0,
        added_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE playback_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id TEXT NOT NULL,
        completion_rate REAL NOT NULL,
        was_skipped INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (track_id) REFERENCES tracks (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE discovery_cache (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE upload_queue (
        id TEXT PRIMARY KEY,
        track_id TEXT NOT NULL,
        local_file_path TEXT NOT NULL,
        metadata_json TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await db.execute('CREATE INDEX idx_tracks_album ON tracks(album)');
    await db.execute('CREATE INDEX idx_tracks_year ON tracks(year)');
    await db.execute('CREATE INDEX idx_events_track ON playback_events(track_id)');
    await db.execute('CREATE INDEX idx_upload_queue_status ON upload_queue(status)');

    // Seed initial trending lossless tracks (Zero 30s preview URLs)
    final initialTracks = [
      {
        'id': 'deezer:3135556',
        'title': 'One More Time',
        'artists': 'Daft Punk',
        'album': 'Discovery',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a4/c8/10/a4c81069-b5f7-3e11-e406-d2a8ec494a8e/0724384960650.jpg/600x600bb.jpg',
        'duration_seconds': 320,
        'year': 2001,
        'genre': 'Electronic',
        'isrc': 'FRZ030000001',
        'quality': 'flac24Bit',
        'is_downloaded': 0,
        'local_file_path': null,
        'is_favorite': 1,
        'is_offline_pinned': 0,
        'added_at': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
      },
      {
        'id': 'deezer:134814984',
        'title': 'Starboy',
        'artists': 'The Weeknd, Daft Punk',
        'album': 'Starboy',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b4/d8/50/b4d850d9-b003-8255-730c-26ee4e55e4e7/16UMGIM83870.rgb.jpg/600x600bb.jpg',
        'duration_seconds': 230,
        'year': 2016,
        'genre': 'R&B/Soul',
        'isrc': 'USUM71607007',
        'quality': 'flac24Bit',
        'is_downloaded': 0,
        'local_file_path': null,
        'is_favorite': 1,
        'is_offline_pinned': 0,
        'added_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      },
      {
        'id': 'deezer:857904',
        'title': 'Time',
        'artists': 'Hans Zimmer',
        'album': 'Inception (Music from the Motion Picture)',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/4a/01/a5/4a01a5dc-4c40-0259-ee44-934fa79321ef/093624965152.jpg/600x600bb.jpg',
        'duration_seconds': 275,
        'year': 2010,
        'genre': 'Soundtrack',
        'isrc': 'USWB11001925',
        'quality': 'flac24Bit',
        'is_downloaded': 0,
        'local_file_path': null,
        'is_favorite': 1,
        'is_offline_pinned': 0,
        'added_at': DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String(),
      },
    ];

    for (final track in initialTracks) {
      await db.insert('tracks', track, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  @override
  Future<List<Track>> getRecentTracks({int limit = 20}) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      orderBy: 'added_at DESC',
      limit: limit,
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> getFavorites() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'is_favorite = 1',
      orderBy: 'added_at DESC',
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> getDownloadedTracks() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'is_downloaded = 1',
      orderBy: 'added_at DESC',
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<void> toggleFavorite(String trackId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'tracks',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  @override
  Future<void> setDownloadState(String trackId, {required bool isDownloaded, String? localFilePath}) async {
    final db = await database;
    await db.update(
      'tracks',
      {
        'is_downloaded': isDownloaded ? 1 : 0,
        'local_file_path': localFilePath,
      },
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  @override
  Future<void> reconcileDownloads() async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'is_downloaded = 1',
    );

    for (final row in results) {
      final path = row['local_file_path'] as String?;
      final id = row['id'] as String;
      if (path == null || !File(path).existsSync()) {
        await db.update(
          'tracks',
          {'is_downloaded': 0, 'local_file_path': null},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  @override
  Future<List<Track>> getTracksByAlbum(String album) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'album = ?',
      whereArgs: [album],
      orderBy: 'year ASC, id ASC',
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> getTracksByArtist(String artist) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'artists LIKE ?',
      whereArgs: ['%$artist%'],
      orderBy: 'year DESC',
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysUnplayed)).toIso8601String();

    final results = await db.rawQuery('''
      SELECT t.*
      FROM tracks t
      LEFT JOIN (
        SELECT track_id, MAX(timestamp) as last_played
        FROM playback_events
        GROUP BY track_id
      ) p ON t.id = p.track_id
      WHERE p.last_played IS NULL OR p.last_played < ?
      ORDER BY RANDOM()
      LIMIT ?
    ''', [cutoffDate, limit]);

    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> searchLocalTracks(String query) async {
    final db = await database;
    final pattern = '%$query%';
    final results = await db.query(
      'tracks',
      where: 'title LIKE ? OR artists LIKE ? OR album LIKE ?',
      whereArgs: [pattern, pattern, pattern],
      limit: 50,
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<void> recordPlaybackEvent({
    required String trackId,
    required double completionRate,
    required bool wasSkipped,
    required DateTime timestamp,
  }) async {
    final db = await database;
    await db.insert('playback_events', {
      'track_id': trackId,
      'completion_rate': completionRate,
      'was_skipped': wasSkipped ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  Future<Map<String, double>> getGenreAffinityScores() async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT t.genre, COUNT(e.id) as play_count, AVG(e.completion_rate) as avg_completion
      FROM playback_events e
      JOIN tracks t ON e.track_id = t.id
      WHERE t.genre IS NOT NULL AND e.was_skipped = 0
      GROUP BY t.genre
    ''');

    final scores = <String, double>{};
    for (final row in results) {
      final genre = row['genre'] as String?;
      if (genre == null) continue;
      final playCount = (row['play_count'] as num).toDouble();
      final avgCompletion = (row['avg_completion'] as num).toDouble();
      scores[genre] = playCount * avgCompletion;
    }
    return scores;
  }

  @override
  Future<List<Track>> getHighAffinityTracks({int limit = 50}) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT t.*, COUNT(e.id) as total_plays
      FROM tracks t
      JOIN playback_events e ON t.id = e.track_id
      WHERE e.was_skipped = 0
      GROUP BY t.id
      ORDER BY total_plays DESC, AVG(e.completion_rate) DESC
      LIMIT ?
    ''', [limit]);

    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<void> upsertTracks(List<Track> tracks) async {
    final db = await database;
    final batch = db.batch();
    for (final track in tracks) {
      batch.insert(
        'tracks',
        track.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> markTrackOfflinePinned(String trackId, bool isPinned) async {
    final db = await database;
    await db.update(
      'tracks',
      {'is_offline_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  @override
  Future<void> removeTrack(String trackId) async {
    final db = await database;
    await db.delete('tracks', where: 'id = ?', whereArgs: [trackId]);
  }

  @override
  Future<void> setCacheData(String key, String data, {Duration expiresIn = const Duration(hours: 24)}) async {
    final db = await database;
    final expiresAt = DateTime.now().add(expiresIn).toIso8601String();
    await db.insert('discovery_cache', {
      'id': key,
      'data': data,
      'expires_at': expiresAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> getCacheData(String key) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final results = await db.query(
      'discovery_cache',
      where: 'id = ? AND expires_at > ?',
      whereArgs: [key, now],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return results.first['data'] as String;
  }

  @override
  Future<void> enqueueUploadJob(UploadJob job) async {
    final db = await database;
    await db.insert('upload_queue', job.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<UploadJob?> dequeueNextUploadJob() async {
    final db = await database;
    final results = await db.query(
      'upload_queue',
      where: "status = 'pending'",
      orderBy: 'attempts ASC, id ASC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return UploadJob.fromMap(results.first);
  }

  @override
  Future<void> updateUploadJobStatus(String jobId, String status, {bool incrementAttempts = false}) async {
    final db = await database;
    final updates = <String, dynamic>{'status': status};
    if (incrementAttempts) {
      await db.rawUpdate('''
        UPDATE upload_queue
        SET status = ?, attempts = attempts + 1
        WHERE id = ?
      ''', [status, jobId]);
    } else {
      await db.update('upload_queue', updates, where: 'id = ?', whereArgs: [jobId]);
    }
  }

  @override
  Future<void> removeUploadJob(String jobId) async {
    final db = await database;
    await db.delete('upload_queue', where: 'id = ?', whereArgs: [jobId]);
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
