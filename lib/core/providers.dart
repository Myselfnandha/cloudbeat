import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/acquisition/native_acquisition_service.dart';
import 'contracts/acquisition_contract.dart';
import 'contracts/audio_contract.dart';
import 'contracts/catalog_contract.dart';
import 'contracts/models.dart';
import 'database/app_database.dart';
import 'ffi/acquisition_ffi.dart';
import '../features/audio_player/cloudbeat_audio_engine.dart';
import '../features/audio_player/cloudbeat_audio_handler.dart';
import '../features/audio_player/player_bloc.dart';
import '../features/discovery/discovery_service.dart';
import '../features/lyrics/unified_lyrics_service.dart';
import '../features/acquisition/ingestion_state_provider.dart';
import '../features/acquisition/ingestion_worker.dart';
import '../features/library/download_manager.dart';
import 'contracts/lyrics_contract.dart';

/// Provides the singleton [AppDatabase] instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Exposes the locked [CatalogContract] to all feature modules.
final catalogContractProvider = Provider<CatalogContract>((ref) {
  return ref.watch(appDatabaseProvider);
});

/// Exposes the locked [AcquisitionContract] for SpotiFLAC multi-backend searches.
final acquisitionContractProvider = Provider<AcquisitionContract>((ref) {
  final ffi = AcquisitionFfiBridge.instance();
  return NativeAcquisitionService(ffi);
});

/// Provides the central [PlayerBloc] instance.
final playerBlocProvider = Provider<PlayerBloc>((ref) {
  return PlayerBloc();
});

/// Provides the singleton [IngestionWorker] / DownloadWorker.
final ingestionWorkerProvider = Provider<IngestionWorker>((ref) {
  final acquisition = ref.watch(acquisitionContractProvider);
  final catalog = ref.watch(catalogContractProvider);
  return IngestionWorker(
    acquisition: acquisition,
    catalog: catalog,
  );
});

/// Provides the [DownloadManager] for offline storage management.
final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  return DownloadManager(
    catalog: catalog,
    acquisition: acquisition,
  );
});

/// Active Audio Quality Mode selector
final audioQualityModeProvider = StateProvider<AudioQualityMode>((ref) {
  return AudioQualityMode.maxLossless;
});

/// Optional [CloudBeatAudioHandler] for Android background MediaSession.
final audioHandlerProvider = Provider<CloudBeatAudioHandler?>((ref) {
  return null;
});

/// Exposes the locked [AudioEngineContract] to UI Shell and widgets.
final audioEngineProvider = Provider<AudioEngineContract>((ref) {
  final bloc = ref.watch(playerBlocProvider);
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  final ingestion = ref.watch(ingestionWorkerProvider);
  final audioHandler = ref.watch(audioHandlerProvider);
  final qualityMode = ref.watch(audioQualityModeProvider);
  return CloudBeatAudioEngine(
    bloc: bloc, 
    catalog: catalog, 
    acquisition: acquisition,
    ingestion: ingestion,
    audioHandler: audioHandler,
    qualityMode: qualityMode,
  );
});

/// Exposes [DiscoveryService] for ML Daily Mixes and Infinite Auto-Radio.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  return DiscoveryService(catalog: catalog, acquisition: acquisition);
});

/// Exposes the locked [LyricsContract] for multi-source synced lyrics.
final lyricsContractProvider = Provider<LyricsContract>((ref) {
  return UnifiedLyricsService();
});

/// Exposes the reactive [IngestionStateNotifier] for 1-tap download ingestion.
final ingestionStateProvider = StateNotifierProvider<IngestionStateNotifier, Map<String, IngestionStatus>>((ref) {
  final worker = ref.watch(ingestionWorkerProvider);
  return IngestionStateNotifier(worker);
});

/// Stream of currently playing track
final currentTrackStreamProvider = StreamProvider<Track?>((ref) {
  final audioEngine = ref.watch(audioEngineProvider);
  return audioEngine.currentTrackStream;
});

/// Automatically fetches and caches lyrics for the currently playing track.
final currentTrackLyricsProvider = FutureProvider<LyricsResult?>((ref) async {
  final lyricsService = ref.watch(lyricsContractProvider);
  final track = ref.watch(currentTrackStreamProvider).value;

  if (track == null) return null;
  return lyricsService.fetchLyrics(track);
});
