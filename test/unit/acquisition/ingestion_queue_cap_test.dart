import 'dart:async';
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
    tempDir = await Directory.systemTemp.createTemp('ingestion_cap_test_');

    when(() => mockAcquisition.purgeTempDirectory()).thenAnswer((_) async {});
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  ExternalTrackResult createTrackResult(String id, String title) {
    return ExternalTrackResult(
      id: id,
      title: title,
      artists: ['Test Artist'],
      album: 'Test Album',
      durationSeconds: 200,
      backend: 'deezer',
      availableQualities: [AudioQuality.flac16Bit],
    );
  }

  AcquiredAudioFiles createPayload(String id, String title) {
    final flac = File('${tempDir.path}/$id.flac');
    final opus = File('${tempDir.path}/$id.opus');
    flac.writeAsStringSync('flac-$id');
    opus.writeAsStringSync('opus-$id');

    final track = Track(
      id: id,
      title: title,
      artists: ['Test Artist'],
      album: 'Test Album',
      durationSeconds: 200,
      addedAt: DateTime.now(),
    );

    return AcquiredAudioFiles(
      track: track,
      flacFile: flac,
      opusFile: opus,
      acquiredQuality: AudioQuality.flac16Bit,
    );
  }

  test('Enforces max 2 unstarted auto-cache tasks and evicts oldest auto-cache task', () async {
    final track1 = createTrackResult('t1', 'Track 1');
    final track2 = createTrackResult('t2', 'Track 2');
    final track3 = createTrackResult('t3', 'Track 3');
    final track4 = createTrackResult('t4', 'Track 4');

    final t1Completer = Completer<AcquiredAudioFiles>();

    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track1))
        .thenAnswer((_) => t1Completer.future);
    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track2))
        .thenAnswer((_) async => createPayload('t2', 'Track 2'));
    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track3))
        .thenAnswer((_) async => createPayload('t3', 'Track 3'));
    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track4))
        .thenAnswer((_) async => createPayload('t4', 'Track 4'));

    when(() => mockCatalog.upsertTracks(any())).thenAnswer((_) async {});

    final worker = IngestionWorker(
      acquisition: mockAcquisition,
      catalog: mockCatalog,
    );

    // Track 1 starts processing and blocks on t1Completer
    final f1 = worker.ingestTrack(track1, isAutoVault: true);

    // Give microtask queue time to start track 1
    await Future.delayed(const Duration(milliseconds: 10));

    // Enqueue 3 more auto-vault tasks while track 1 is running:
    // Queue should hold track 2 and track 3 (cap of 2 pending auto-vault tasks).
    // When track 4 is enqueued, track 2 (oldest pending auto-vault) must be evicted with Exception.
    final f2 = worker.ingestTrack(track2, isAutoVault: true);
    final f3 = worker.ingestTrack(track3, isAutoVault: true);
    final f4 = worker.ingestTrack(track4, isAutoVault: true);

    // Track 2 should complete with error due to eviction
    expect(f2, throwsA(isA<Exception>()));

    // Complete track 1
    t1Completer.complete(createPayload('t1', 'Track 1'));
    await f1;

    // Remaining tasks 3 and 4 should complete successfully
    final res3 = await f3;
    final res4 = await f4;
    expect(res3.id, equals('t3'));
    expect(res4.id, equals('t4'));
  });

  test('Promotes existing queued auto-cache task to explicit on user tap and prioritizes it', () async {
    final track1 = createTrackResult('t1', 'Track 1');
    final track2 = createTrackResult('t2', 'Track 2');
    final track3 = createTrackResult('t3', 'Track 3');

    final t1Completer = Completer<AcquiredAudioFiles>();

    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track1))
        .thenAnswer((_) => t1Completer.future);
    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track2))
        .thenAnswer((_) async => createPayload('t2', 'Track 2'));
    when(() => mockAcquisition.acquireLosslessTrack(trackResult: track3))
        .thenAnswer((_) async => createPayload('t3', 'Track 3'));

    when(() => mockCatalog.upsertTracks(any())).thenAnswer((_) async {});

    final worker = IngestionWorker(
      acquisition: mockAcquisition,
      catalog: mockCatalog,
    );

    // Start track 1 (running)
    final f1 = worker.ingestTrack(track1, isAutoVault: true);
    await Future.delayed(const Duration(milliseconds: 10));

    // Enqueue track 2 as auto-vault, then track 3 as auto-vault
    final f2Auto = worker.ingestTrack(track2, isAutoVault: true);
    final f3Auto = worker.ingestTrack(track3, isAutoVault: true);

    // User explicitly taps on Track 3!
    // Should promote track 3 to explicit (isAutoVault: false), move to front of queue ahead of track 2
    final f3Explicit = worker.ingestTrack(track3, isAutoVault: false);

    // Both futures for Track 3 should refer to the same job
    expect(identical(f3Auto, f3Explicit), isTrue);

    // Unblock track 1
    t1Completer.complete(createPayload('t1', 'Track 1'));
    await f1;

    final res3 = await f3Explicit;
    final res2 = await f2Auto;

    expect(res3.id, equals('t3'));
    expect(res2.id, equals('t2'));
  });
}
