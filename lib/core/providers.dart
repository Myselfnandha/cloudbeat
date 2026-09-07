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
import '../features/discovery/innertube_service.dart';
import '../features/lyrics/unified_lyrics_service.dart';
import '../features/acquisition/ingestion_state_provider.dart';
import '../features/acquisition/ingestion_worker.dart';
import '../features/library/download_manager.dart';
import 'contracts/lyrics_contract.dart';
import 'session/zarz_session_manager.dart';
import 'services/sponsorblock_service.dart';
import 'services/cobalt_stream_resolver.dart';

/// Provides the singleton [AppDatabase] instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Exposes the locked [CatalogContract] to all feature modules.
final catalogContractProvider = Provider<CatalogContract>((ref) {
  return ref.watch(appDatabaseProvider);
});

/// Clean Stream Purity filter toggle (SponsorBlock)
final cleanStreamEnabledProvider = StateProvider<bool>((ref) {
  return true;
});

/// Custom Cobalt instance URL provider
final cobaltInstanceUrlProvider = StateProvider<String>((ref) {
  return '';
});

/// Provides the ZarzSessionManager singleton.
final zarzSessionManagerProvider = Provider<ZarzSessionManager>((ref) {
  final mgr = ZarzSessionManager();
  mgr.initialize();
  return mgr;
});

/// Exposes the locked [AcquisitionContract] for SpotiFLAC multi-backend searches.
final acquisitionContractProvider = Provider<AcquisitionContract>((ref) {
  final ffi = AcquisitionFfiBridge.instance();
  final zarzSession = ref.watch(zarzSessionManagerProvider);
  final customCobalt = ref.watch(cobaltInstanceUrlProvider);
  final cobalt = CobaltStreamResolver(customInstance: customCobalt);
  return NativeAcquisitionService(
    ffi,
    zarzSession: zarzSession,
    cobaltResolver: cobalt,
  );
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
  final cleanStreamEnabled = ref.watch(cleanStreamEnabledProvider);

  return CloudBeatAudioEngine(
    bloc: bloc, 
    catalog: catalog, 
    acquisition: acquisition,
    ingestion: ingestion,
    audioHandler: audioHandler,
    qualityMode: qualityMode,
    sponsorBlock: SponsorBlockService(enabled: cleanStreamEnabled),
  );
});

/// Exposes [DiscoveryService] for ML Daily Mixes and Infinite Auto-Radio.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  return DiscoveryService(catalog: catalog, acquisition: acquisition);
});

/// Exposes the singleton [InnerTubeService] for discovery and search suggestions.
final innerTubeServiceProvider = Provider<InnerTubeService>((ref) {
  return InnerTubeService();
});

/// Selected mood filter chip on Home screen
final selectedMoodFilterProvider = StateProvider<String?>((ref) {
  return null;
});

/// Player background style: 'meshGradient', 'solidDynamic', 'darkGlass'
final playerBackgroundStyleProvider = StateProvider<String>((ref) {
  return 'meshGradient';
});

/// Singleton [UnifiedLyricsService] with multi-provider waterfall
final unifiedLyricsServiceProvider = Provider<UnifiedLyricsService>((ref) {
  return UnifiedLyricsService();
});

/// Exposes the locked [LyricsContract] for multi-source synced lyrics.
final lyricsContractProvider = Provider<LyricsContract>((ref) {
  return ref.watch(unifiedLyricsServiceProvider);
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
