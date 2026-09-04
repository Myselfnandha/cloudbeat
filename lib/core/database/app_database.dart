import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../contracts/catalog_contract.dart';
import '../contracts/models.dart';

class AppDatabase implements CatalogContract {
  static AppDatabase? _instance;
  Database? _db;

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
    _db = await _initDatabase();
    return _db!;
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

    await db.execute('CREATE INDEX idx_tracks_album ON tracks(album)');
    await db.execute('CREATE INDEX idx_tracks_year ON tracks(year)');
    await db.execute('CREATE INDEX idx_events_track ON playback_events(track_id)');
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

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
