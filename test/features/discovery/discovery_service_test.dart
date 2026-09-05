import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:cloudbeat/core/contracts/acquisition_contract.dart';
import 'package:cloudbeat/core/contracts/catalog_contract.dart';
import 'package:cloudbeat/core/contracts/models.dart';
import 'package:cloudbeat/features/discovery/discovery_service.dart';

class MockCatalogContract extends Mock implements CatalogContract {}
class MockAcquisitionContract extends Mock implements AcquisitionContract {}

void main() {
  late MockCatalogContract mockCatalog;
  late MockAcquisitionContract mockAcquisition;
  late DiscoveryService discoveryService;

  final sampleTracks = [
    Track(
      id: 't1',
      title: 'Hukum',
      artists: ['Anirudh'],
      album: 'Jailer',
      durationSeconds: 210,
      genre: 'Soundtrack',
      addedAt: DateTime.now(),
    ),
    Track(
      id: 't2',
      title: 'Chill Track',
      artists: ['Acoustic Artist'],
      album: 'Acoustic Vibes',
      durationSeconds: 180,
      genre: 'Acoustic',
      addedAt: DateTime.now(),
    ),
  ];

  setUp(() {
    mockCatalog = MockCatalogContract();
    mockAcquisition = MockAcquisitionContract();
    discoveryService = DiscoveryService(
      catalog: mockCatalog,
      acquisition: mockAcquisition,
    );
  });

  test('generateDailyMixes creates 3 distinct mix clusters', () async {
    when(() => mockCatalog.getRecentTracks(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleTracks);
    when(() => mockCatalog.getGenreAffinityScores())
        .thenAnswer((_) async => {'Soundtrack': 10.5, 'Acoustic': 4.2});
    when(() => mockCatalog.getHighAffinityTracks(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleTracks);
    when(() => mockCatalog.getForgottenGems(
          daysUnplayed: any(named: 'daysUnplayed'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [sampleTracks.first]);

    final mixes = await discoveryService.generateDailyMixes();

    expect(mixes.length, 3);
    expect(mixes[0].title.contains('Soundtrack'), true);
    expect(mixes[1].title.contains('Rewind Library'), true);
    expect(mixes[2].title.contains('Chill & Unwind'), true);
  });

  test('generateAutoRadio selects contextually matching seed tracks', () async {
    when(() => mockCatalog.getTracksByArtist('Anirudh'))
        .thenAnswer((_) async => [sampleTracks.first]);
    when(() => mockCatalog.getHighAffinityTracks(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleTracks);
    when(() => mockCatalog.getRecentTracks(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleTracks);

    final radio = await discoveryService.generateAutoRadio(sampleTracks.first);
    expect(radio.isNotEmpty, true);
  });
}
