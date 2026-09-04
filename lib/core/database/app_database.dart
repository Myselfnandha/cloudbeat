import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../contracts/catalog_contract.dart';
import '../contracts/models.dart';

class AppDatabase implements CatalogContract {
  static AppDatabase? _instance;
  Database? _db;
  Completer<Database>? _openCompleter;

  AppDatabase._();

  static AppDatabase get instance => _instance ??= AppDatabase._();

  static void initializeForTesting({Database? db}) {
    _instance = AppDatabase._();
    if (db != null) {
      _instance!._db = db;
    }
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    if (_openCompleter != null) return _openCompleter!.future;

    _openCompleter = Completer<Database>();
    try {
      _db = await _initDatabase();
      _openCompleter!.complete(_db);
      return _db!;
    } catch (e, st) {
      _openCompleter!.completeError(e, st);
      _openCompleter = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase({String? customPath, bool inMemory = false}) async {
    // Enable FFI on Linux and Windows desktop harnesses
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    if (inMemory) {
      return await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: _onCreate,
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
      version: 1,
      onCreate: _onCreate,
    );
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
        telegram_chat_id INTEGER,
        telegram_message_id INTEGER,
        flac_file_id TEXT,
        opus_file_id TEXT,
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

    await db.execute('CREATE INDEX idx_tracks_album ON tracks(album)');
    await db.execute('CREATE INDEX idx_tracks_year ON tracks(year)');
    await db.execute('CREATE INDEX idx_events_track ON playback_events(track_id)');

    // Seed initial trending lossless tracks
    final initialTracks = [
      {
        'id': 'seed_daft_punk_one_more_time',
        'title': 'One More Time',
        'artists': 'Daft Punk',
        'album': 'Discovery',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a4/c8/10/a4c81069-b5f7-3e11-e406-d2a8ec494a8e/0724384960650.jpg/600x600bb.jpg',
        'duration_seconds': 320,
        'year': 2001,
        'genre': 'Electronic',
        'isrc': 'FRZ030000001',
        'quality': 'flac24Bit',
        'flac_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/80/7e/61/807e61e6-b072-4d05-4c07-6f9ecb498fce/mzaf_6130982559595180479.plus.aac.p.m4a',
        'opus_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/80/7e/61/807e61e6-b072-4d05-4c07-6f9ecb498fce/mzaf_6130982559595180479.plus.aac.p.m4a',
        'is_offline_pinned': 0,
        'added_at': DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
      },
      {
        'id': 'seed_weeknd_starboy',
        'title': 'Starboy',
        'artists': 'The Weeknd, Daft Punk',
        'album': 'Starboy',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b4/d8/50/b4d850d9-b003-8255-730c-26ee4e55e4e7/16UMGIM83870.rgb.jpg/600x600bb.jpg',
        'duration_seconds': 230,
        'year': 2016,
        'genre': 'R&B/Soul',
        'isrc': 'USUM71607007',
        'quality': 'flac24Bit',
        'flac_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ba/65/5a/ba655a30-c3d5-d8aa-4752-085732152a46/mzaf_10526019688411030107.plus.aac.p.m4a',
        'opus_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/ba/65/5a/ba655a30-c3d5-d8aa-4752-085732152a46/mzaf_10526019688411030107.plus.aac.p.m4a',
        'is_offline_pinned': 0,
        'added_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      },
      {
        'id': 'seed_hans_zimmer_time',
        'title': 'Time',
        'artists': 'Hans Zimmer',
        'album': 'Inception (Music from the Motion Picture)',
        'album_art_url': 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/4a/01/a5/4a01a5dc-4c40-0259-ee44-934fa79321ef/093624965152.jpg/600x600bb.jpg',
        'duration_seconds': 275,
        'year': 2010,
        'genre': 'Soundtrack',
        'isrc': 'USWB11001925',
        'quality': 'flac24Bit',
        'flac_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/05/65/45/05654516-7d12-1f41-0f72-b7b51b75a133/mzaf_13506161989433435848.plus.aac.p.m4a',
        'opus_file_id': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/05/65/45/05654516-7d12-1f41-0f72-b7b51b75a133/mzaf_13506161989433435848.plus.aac.p.m4a',
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
  Future<List<Track>> getTracksByAlbum(String album) async {
    final db = await database;
    final results = await db.query(
      'tracks',
      where: 'album = ?',
      whereArgs: [album],
      orderBy: 'title ASC',
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
      orderBy: 'added_at DESC',
    );
    return results.map((m) => Track.fromMap(m)).toList();
  }

  @override
  Future<List<Track>> getForgottenGems({int daysUnplayed = 30, int limit = 10}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(Duration(days: daysUnplayed)).toIso8601String();

    final results = await db.rawQuery('''
      SELECT t.* FROM tracks t
      LEFT JOIN (
        SELECT track_id, MAX(timestamp) as last_played
        FROM playback_events
        GROUP BY track_id
      ) e ON t.id = e.track_id
      WHERE e.last_played IS NULL OR e.last_played < ?
      ORDER BY RANDOM()
      LIMIT ?
    ''', [cutoff, limit]);

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
    final results = await db.query('discovery_cache', where: 'id = ?', whereArgs: [key]);
    if (results.isEmpty) return null;

    final expiresAtStr = results.first['expires_at'] as String;
    final expiresAt = DateTime.parse(expiresAtStr);
    
    if (DateTime.now().isAfter(expiresAt)) {
      await db.delete('discovery_cache', where: 'id = ?', whereArgs: [key]);
      return null;
    }

    return results.first['data'] as String;
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
