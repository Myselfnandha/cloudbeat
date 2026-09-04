import 'dart:io';
import 'dart:typed_data';
import 'models.dart';

abstract class VaultContract {
  // Authentication & Connection State (Consumed by Module 5 Settings)
  Stream<VaultAuthState> get authStateStream;
  VaultAuthState get currentAuthState;
  Future<void> sendPhoneNumber(String phoneNumber);
  Future<void> sendAuthCode(String code);
  Future<void> sendPassword(String password);
  Future<void> logout();

  // Progressive Chunk Streaming (Consumed directly by TelegramStreamAudioSource in Module 4)
  Future<Uint8List> streamChunk({
    required String fileId,
    required int offset,
    required int length,
  });

  // Uploading Acquired Audio to Telegram Decade Topics (Consumed by Module 2 Ingestion Queue)
  Future<Track> uploadTrackFiles({
    required Track track,
    required File flacFile,
    required File opusFile,
    void Function(double progress)? onProgress,
  });

  // Master Catalog Manifest Sync (<3s library recovery)
  Future<List<Track>> downloadMasterManifest();
  Future<void> publishMasterManifest(List<Track> catalog);

  // Supergroup & Topic Management
  Future<int> getOrCreateDecadeSupergroup(int year);
  Future<int> getOrCreateGenreTopic(int supergroupId, String genreOrLanguage);
}
