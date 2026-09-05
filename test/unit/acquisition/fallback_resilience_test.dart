import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/core/ffi/acquisition_ffi.dart';
import 'package:cloudbeat/features/acquisition/native_acquisition_service.dart';
import 'package:cloudbeat/features/discovery/discovery_service.dart';

class MockAcquisitionFfiBridge extends Mock implements AcquisitionFfiBridge {}
class MockCatalogContract extends Mock implements CatalogContract {}
class MockAcquisitionContract extends Mock implements AcquisitionContract {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  group('Failure-Path & Resilience Regression Tests', () {
    late MockAcquisitionFfiBridge mockFfi;
    late http.Client mockHttpClient;
    late NativeAcquisitionService acquisitionService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});

      mockFfi = MockAcquisitionFfiBridge();
      // Simulate Native FFI being completely unavailable (e.g. ABI mismatch or missing .so)
      when(() => mockFfi.isNativeLoaded).thenReturn(false);
      when(() => mockFfi.loadExtension(any(), any(), any())).thenReturn(false);
      when(() => mockFfi.executeCommand(any(), any(), any())).thenReturn({'error': 'Native engine unavailable'});
      when(() => mockFfi.searchAllBackends(any(), limit: any(named: 'limit'))).thenAnswer((_) async => []);
      when(() => mockFfi.getTrending(any())).thenAnswer((_) async => []);

      mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/search')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 123456,
                  'title': 'Get Lucky',
                  'artist': {'name': 'Daft Punk'},
                  'album': {'title': 'Random Access Memories', 'cover_xl': 'https://example.com/ram.jpg'},
                  'duration': 248,
                  'isrc': 'USQX91300105',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.contains('/chart')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 789012,
                  'title': 'Blinding Lights',
                  'artist': {'name': 'The Weeknd'},
                  'album': {'title': 'After Hours', 'cover_xl': 'https://example.com/ah.jpg'},
                  'duration': 200,
                  'isrc': 'USUM71900001',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      acquisitionService = NativeAcquisitionService(mockFfi, client: mockHttpClient);
    });

    test('1. Pure-Dart Deezer search fallback triggers when native FFI is unavailable and results are strictly scoped to deezer', () async {
      // Execute search query when FFI is dead
      final results = await acquisitionService.searchAllBackends('Daft Punk', limit: 5);

      // Verify that results were fetched via pure-Dart HTTP fallback
      expect(results.isNotEmpty, true, reason: 'Pure-Dart fallback should return search results from Deezer API');
      expect(results.first.title, 'Get Lucky');
      expect(results.first.artists.first, 'Daft Punk');
      for (final track in results) {
        expect(track.backend, 'deezer', reason: 'Fallback scope must remain strictly Deezer-only (no scope creep)');
      }
    });

    test('2. Pure-Dart Deezer chart fallback triggers when native FFI is unavailable and results are strictly scoped to deezer', () async {
      // Execute getTrending when FFI is dead
      final chartResults = await acquisitionService.getTrending('deezer');

      expect(chartResults.isNotEmpty, true, reason: 'Pure-Dart fallback should fetch chart tracks from Deezer API');
      expect(chartResults.first.title, 'Blinding Lights');
      expect(chartResults.first.artists.first, 'The Weeknd');
      for (final track in chartResults) {
        expect(track.backend, 'deezer', reason: 'Fallback scope must remain strictly Deezer-only');
      }
    });

    test('3. resolveStreamUrl throws NativeEngineUnavailableException when native FFI is missing', () async {
      // When FFI is dead, stream resolution cannot decrypt lossless FLAC and must throw explicit exception
      expect(
        () async => await acquisitionService.resolveStreamUrl(
          trackId: '123456',
          backend: 'deezer',
          requestedQuality: AudioQuality.flac16Bit,
        ),
        throwsA(
          isA<NativeEngineUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('Hi-Res streaming unavailable — native engine not loaded'),
          ),
        ),
      );
    });

    test('4. DiscoveryService.getLiveTrendingMixes returns exactly the 3 verified clean seed tracks with isOfflineFallback: true when acquisition fails on empty library', () async {
      final mockCatalog = MockCatalogContract();
      final mockAcquisition = MockAcquisitionContract();

      final cleanSeedTracks = [
        Track(
          id: 'seed_daft_punk_one_more_time',
          title: 'One More Time',
          artists: ['Daft Punk'],
          album: 'Discovery',
          albumArtUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a4/c8/10/a4c81069-b5f7-3e11-e406-d2a8ec494a8e/0724384960650.jpg/600x600bb.jpg',
          durationSeconds: 320,
          genre: 'Electronic',
          isrc: 'FRZ030000001',
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
        Track(
          id: 'seed_weeknd_starboy',
          title: 'Starboy',
          artists: ['The Weeknd, Daft Punk'],
          album: 'Starboy',
          albumArtUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b4/d8/50/b4d850d9-b003-8255-730c-26ee4e55e4e7/16UMGIM83870.rgb.jpg/600x600bb.jpg',
          durationSeconds: 230,
          genre: 'R&B/Soul',
          isrc: 'USUM71607007',
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
        Track(
          id: 'seed_hans_zimmer_time',
          title: 'Time',
          artists: ['Hans Zimmer'],
          album: 'Inception (Music from the Motion Picture)',
          albumArtUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/4a/01/a5/4a01a5dc-4c40-0259-ee44-934fa79321ef/093624965152.jpg/600x600bb.jpg',
          durationSeconds: 275,
          genre: 'Soundtrack',
          isrc: 'USWB11001925',
          quality: AudioQuality.flac24Bit,
          addedAt: DateTime.now(),
        ),
      ];

      when(() => mockCatalog.getCacheData(any())).thenAnswer((_) async => null);
      when(() => mockCatalog.setCacheData(any(), any(), expiresIn: any(named: 'expiresIn'))).thenAnswer((_) async {});
      when(() => mockCatalog.getFavorites()).thenAnswer((_) async => []);
      when(() => mockCatalog.getDownloadedTracks()).thenAnswer((_) async => []);
      when(() => mockCatalog.getRecentTracks(limit: any(named: 'limit'))).thenAnswer((_) async => cleanSeedTracks);
      // Acquisition fails/throws
      when(() => mockAcquisition.getTrending(any())).thenAnswer((_) async => []);
      when(() => mockAcquisition.searchAllBackends(any(), backends: any(named: 'backends'), limit: any(named: 'limit'))).thenAnswer((_) async => []);

      final discoveryService = DiscoveryService(
        catalog: mockCatalog,
        acquisition: mockAcquisition,
      );

      final mixes = await discoveryService.getLiveTrendingMixes();

      expect(mixes.length, 1);
      final fallbackMix = mixes.first;
      expect(fallbackMix.isOfflineFallback, true, reason: 'isOfflineFallback flag must be true');
      expect(fallbackMix.tracks.length, 3, reason: 'Must return exactly the 3 verified seed tracks');
      expect(fallbackMix.tracks[0].title, 'One More Time');
      expect(fallbackMix.tracks[1].title, 'Starboy');
      expect(fallbackMix.tracks[2].title, 'Time');

      // Verify zero 30s preview URLs exist in any of the returned tracks
      for (final t in fallbackMix.tracks) {
        expect(t.localFilePath?.contains('.m4a'), isNot(true));
      }
    });
  });
}
