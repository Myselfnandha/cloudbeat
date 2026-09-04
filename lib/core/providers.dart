import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'contracts/acquisition_contract.dart';
import 'contracts/audio_contract.dart';
import 'contracts/catalog_contract.dart';
import 'contracts/vault_contract.dart';
import 'database/app_database.dart';
import 'ffi/acquisition_ffi.dart';
import '../features/audio_player/cloudbeat_audio_engine.dart';
import '../features/audio_player/player_bloc.dart';
import '../features/discovery/discovery_service.dart';
import '../features/telegram_vault/native_telegram_vault_service.dart';
import '../features/acquisition/ingestion_worker.dart';

/// Provides the singleton [AppDatabase] instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Exposes the locked [CatalogContract] to all feature modules.
final catalogContractProvider = Provider<CatalogContract>((ref) {
  return ref.watch(appDatabaseProvider);
});

/// Exposes the locked [VaultContract] for Telegram MTProto / local streaming.
final vaultContractProvider = Provider<VaultContract>((ref) {
  return NativeTelegramVaultService();
});

/// Exposes the locked [AcquisitionContract] for SpotiFLAC multi-backend searches.
final acquisitionContractProvider = Provider<AcquisitionContract>((ref) {
  return AcquisitionFfiBridge.instance();
});

/// Provides the central [PlayerBloc] instance.
final playerBlocProvider = Provider<PlayerBloc>((ref) {
  return PlayerBloc();
});

/// Provides the singleton [IngestionWorker].
final ingestionWorkerProvider = Provider<IngestionWorker>((ref) {
  final acquisition = ref.watch(acquisitionContractProvider);
  final vault = ref.watch(vaultContractProvider);
  final catalog = ref.watch(catalogContractProvider);
  return IngestionWorker(
    acquisition: acquisition,
    vault: vault,
    catalog: catalog,
  );
});

/// Exposes the locked [AudioEngineContract] to UI Shell and widgets.
final audioEngineProvider = Provider<AudioEngineContract>((ref) {
  final bloc = ref.watch(playerBlocProvider);
  final vault = ref.watch(vaultContractProvider);
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  final ingestion = ref.watch(ingestionWorkerProvider);
  return CloudBeatAudioEngine(
    bloc: bloc, 
    vault: vault, 
    catalog: catalog, 
    acquisition: acquisition,
    ingestion: ingestion,
  );
});

/// Exposes [DiscoveryService] for ML Daily Mixes and Infinite Auto-Radio.
final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final catalog = ref.watch(catalogContractProvider);
  final acquisition = ref.watch(acquisitionContractProvider);
  return DiscoveryService(catalog: catalog, acquisition: acquisition);
});
