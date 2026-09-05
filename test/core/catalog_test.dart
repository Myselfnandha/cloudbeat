import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('CatalogContract & SQLite AppDatabase Tests', () {
    late AppDatabase catalog;
    late Database testDb;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
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
          },
        ),
      );

      AppDatabase.initializeForTesting(db: testDb);
      catalog = AppDatabase.instance;
    });

    tearDown(() async {
      await testDb.close();
    });

    test('upsertTracks and getRecentTracks', () async {
      final track1 = Track(
        id: 'track_1',
        title: 'Song A',
        artists: ['Artist A'],
        album: 'Album 1',
        durationSeconds: 180,
        year: 2025,
        genre: 'Soundtrack',
        addedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final track2 = Track(
        id: 'track_2',
        title: 'Song B',
        artists: ['Artist B', 'Featured C'],
        album: 'Album 2',
        durationSeconds: 220,
        year: 2026,
        genre: 'Acoustic',
        addedAt: DateTime.now(),
      );

      await catalog.upsertTracks([track1, track2]);

      final recent = await catalog.getRecentTracks();
      expect(recent.length, 2);
      expect(recent.first.id, 'track_2'); // More recent first

      final byAlbum = await catalog.getTracksByAlbum('Album 1');
      expect(byAlbum.length, 1);
      expect(byAlbum.first.title, 'Song A');

      final search = await catalog.searchLocalTracks('Featured');
      expect(search.length, 1);
      expect(search.first.id, 'track_2');
    });

    test('Telemetry recording and genre affinity calculation', () async {
      final track1 = Track(
        id: 't1',
        title: 'Soundtrack Hit',
        artists: ['Composer'],
        album: 'OST',
        durationSeconds: 200,
        genre: 'OST',
        addedAt: DateTime.now(),
      );

      final track2 = Track(
        id: 't2',
        title: 'Rock Track',
        artists: ['Rocker'],
        album: 'Rock Album',
        durationSeconds: 150,
        genre: 'Rock',
        addedAt: DateTime.now(),
      );

      await catalog.upsertTracks([track1, track2]);

      // Record telemetry
      await catalog.recordPlaybackEvent(
        trackId: 't1',
        completionRate: 1.0,
        wasSkipped: false,
        timestamp: DateTime.now(),
      );
      await catalog.recordPlaybackEvent(
        trackId: 't1',
        completionRate: 0.9,
        wasSkipped: false,
        timestamp: DateTime.now(),
      );
      await catalog.recordPlaybackEvent(
        trackId: 't2',
        completionRate: 0.2,
        wasSkipped: true, // Skipped should not contribute to positive affinity
        timestamp: DateTime.now(),
      );

      final scores = await catalog.getGenreAffinityScores();
      expect(scores.containsKey('OST'), true);
      expect(scores['OST']!, greaterThan(1.5));
      expect(scores.containsKey('Rock'), false); // Was skipped

      final highAffinity = await catalog.getHighAffinityTracks();
      expect(highAffinity.length, 1);
      expect(highAffinity.first.id, 't1');
    });

    test('markTrackOfflinePinned updates pin status', () async {
      final track = Track(
        id: 'pinned_t',
        title: 'Offline Favorite',
        artists: ['Artist'],
        album: 'Album',
        durationSeconds: 190,
        addedAt: DateTime.now(),
      );

      await catalog.upsertTracks([track]);
      await catalog.markTrackOfflinePinned('pinned_t', true);

      final recent = await catalog.getRecentTracks();
      expect(recent.first.isOfflinePinned, true);

      await catalog.markTrackOfflinePinned('pinned_t', false);
      final unpinned = await catalog.getRecentTracks();
      expect(unpinned.first.isOfflinePinned, false);
    });

    test('favorites and download state management', () async {
      final track = Track(
        id: 'fav_track_1',
        title: 'Lossless Track',
        artists: ['HiFi Artist'],
        album: 'HiFi Album',
        durationSeconds: 210,
        addedAt: DateTime.now(),
      );

      await catalog.upsertTracks([track]);

      // Initially not favorite
      var favs = await catalog.getFavorites();
      expect(favs.isEmpty, true);

      // Toggle favorite ON
      await catalog.toggleFavorite('fav_track_1', true);
      favs = await catalog.getFavorites();
      expect(favs.length, 1);
      expect(favs.first.id, 'fav_track_1');
      expect(favs.first.isFavorite, true);

      // Set download state
      await catalog.setDownloadState('fav_track_1', isDownloaded: true, localFilePath: '/music/fav_1.flac');
      var downloaded = await catalog.getDownloadedTracks();
      expect(downloaded.length, 1);
      expect(downloaded.first.isDownloaded, true);
      expect(downloaded.first.localFilePath, '/music/fav_1.flac');

      // Toggle favorite OFF
      await catalog.toggleFavorite('fav_track_1', false);
      favs = await catalog.getFavorites();
      expect(favs.isEmpty, true);
    });
  });
}
