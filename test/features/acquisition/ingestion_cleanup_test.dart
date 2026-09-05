import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/acquisition/ingestion_worker.dart';

class MockAcquisitionContract extends Mock implements AcquisitionContract {}
class MockCatalogContract extends Mock implements CatalogContract {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAcquisitionContract mockAcquisition;
  late MockCatalogContract mockCatalog;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(Track(
      id: 'fallback',
      title: 'fallback',
      artists: [],
      album: 'fallback',
      durationSeconds: 0,
      addedAt: DateTime.now(),
    ));
    registerFallbackValue(File(''));
  });

  setUp(() async {
    mockAcquisition = MockAcquisitionContract();
    mockCatalog = MockCatalogContract();
    tempDir = await Directory.systemTemp.createTemp('ingestion_cleanup_test_');

    when(() => mockAcquisition.purgeTempDirectory()).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Successful ingestion downloads track and cleans up scratch temp files in finally block', () async {
    final flac = File('${tempDir.path}/track1.flac');
    final opus = File('${tempDir.path}/track1.opus');
    await flac.writeAsString('flac content');
    await opus.writeAsString('opus content');

    final testTrack = Track(
      id: 'track1',
      title: 'Coolie',
      artists: ['Anirudh'],
      album: 'Coolie',
      durationSeconds: 200,
      addedAt: DateTime.now(),
    );

    final payload = AcquiredAudioFiles(
      track: testTrack,
      flacFile: flac,
      opusFile: opus,
      acquiredQuality: AudioQuality.flac24Bit,
    );

    final trackResult = ExternalTrackResult(
      id: 'track1',
      title: 'Coolie',
      artists: ['Anirudh'],
      album: 'Coolie',
      durationSeconds: 200,
      backend: 'deezer',
      availableQualities: [AudioQuality.flac24Bit],
    );

    when(() => mockAcquisition.acquireLosslessTrack(trackResult: trackResult))
        .thenAnswer((_) async => payload);

    when(() => mockCatalog.upsertTracks(any())).thenAnswer((_) async {});

    final worker = IngestionWorker(
      acquisition: mockAcquisition,
      catalog: mockCatalog,
    );

    expect(await flac.exists(), true);
    expect(await opus.exists(), true);

    final result = await worker.ingestTrack(trackResult);

    expect(result.id, 'track1');
    expect(result.isDownloaded, true);

    // Verify scratch temp files were deleted automatically by finally block
    expect(await flac.exists(), false);
    expect(await opus.exists(), false);
  });

  test('Failed catalog upsert STILL deletes temp files in finally block to prevent disk leak', () async {
    final flac = File('${tempDir.path}/track_err.flac');
    final opus = File('${tempDir.path}/track_err.opus');
    await flac.writeAsString('flac content');
    await opus.writeAsString('opus content');

    final testTrack = Track(
      id: 'track_err',
      title: 'Error Song',
      artists: ['Artist'],
      album: 'Album',
      durationSeconds: 150,
      addedAt: DateTime.now(),
    );

    final payload = AcquiredAudioFiles(
      track: testTrack,
      flacFile: flac,
      opusFile: opus,
      acquiredQuality: AudioQuality.flac16Bit,
    );

    final trackResult = ExternalTrackResult(
      id: 'track_err',
      title: 'Error Song',
      artists: ['Artist'],
      album: 'Album',
      durationSeconds: 150,
      backend: 'deezer',
      availableQualities: [AudioQuality.flac16Bit],
    );

    when(() => mockAcquisition.acquireLosslessTrack(trackResult: trackResult))
        .thenAnswer((_) async => payload);

    when(() => mockCatalog.upsertTracks(any())).thenThrow(const SocketException('Disk write failed'));

    final worker = IngestionWorker(
      acquisition: mockAcquisition,
      catalog: mockCatalog,
    );

    expect(await flac.exists(), true);
    expect(await opus.exists(), true);

    await expectLater(
      worker.ingestTrack(trackResult),
      throwsA(isA<SocketException>()),
    );

    // Even though upsert threw, finally block MUST delete temp scratch files
    expect(await flac.exists(), false);
    expect(await opus.exists(), false);
  });
}
