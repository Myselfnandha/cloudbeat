import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import '../../core/contracts/models.dart';
import '../../core/contracts/vault_contract.dart';

class TelegramVaultService implements VaultContract {
  final _authStateController = StreamController<VaultAuthState>.broadcast();
  VaultAuthState _currentState = VaultAuthState.unauthenticated;

  // In-memory registry of decade supergroups and genre topics
  final Map<int, int> _decadeSupergroups = {}; // year -> supergroupChatId
  final Map<String, int> _genreTopics = {};    // "supergroupId:genre" -> topicId
  final List<Track> _masterManifest = [];

  TelegramVaultService() {
    // Default desktop harness / test state starts in unauthenticated
    _authStateController.add(_currentState);
  }

  @override
  Stream<VaultAuthState> get authStateStream => _authStateController.stream;

  @override
  VaultAuthState get currentAuthState => _currentState;

  @override
  Future<void> sendPhoneNumber(String phoneNumber) async {
    // Transition to waiting for SMS/Telegram auth code
    _currentState = VaultAuthState.waitCode;
    _authStateController.add(_currentState);
  }

  @override
  Future<void> sendAuthCode(String code) async {
    // Transition to authenticated (or waitPassword if 2FA is needed)
    if (code == '2FA') {
      _currentState = VaultAuthState.waitPassword;
    } else {
      _currentState = VaultAuthState.authenticated;
    }
    _authStateController.add(_currentState);
  }

  @override
  Future<void> sendPassword(String password) async {
    _currentState = VaultAuthState.authenticated;
    _authStateController.add(_currentState);
  }

  @override
  Future<void> logout() async {
    _currentState = VaultAuthState.unauthenticated;
    _authStateController.add(_currentState);
  }

  @override
  Future<Uint8List> streamChunk({
    required String fileId,
    required int offset,
    required int length,
  }) async {
    // For local desktop mock or tests, return deterministic synthetic audio bytes
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = (offset + i) % 256;
    }
    return bytes;
  }

  @override
  Future<Track> uploadTrackFiles({
    required Track track,
    required File flacFile,
    required File opusFile,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);

    final decadeSupergroupId = await getOrCreateDecadeSupergroup(track.year ?? 2026);
    await getOrCreateGenreTopic(decadeSupergroupId, track.genre ?? 'General');

    // Simulate Telegram message and file ID allocation
    final randomMessageId = Random().nextInt(900000) + 100000;
    final flacId = 'tg_flac_${track.id}_${DateTime.now().millisecondsSinceEpoch}';
    final opusId = 'tg_opus_${track.id}_${DateTime.now().millisecondsSinceEpoch}';

    onProgress?.call(1.0);

    final uploadedTrack = track.copyWith(
      telegramChatId: decadeSupergroupId,
      telegramMessageId: randomMessageId,
      flacFileId: flacId,
      opusFileId: opusId,
    );

    _masterManifest.add(uploadedTrack);
    return uploadedTrack;
  }

  @override
  Future<List<Track>> downloadMasterManifest() async {
    return List.unmodifiable(_masterManifest);
  }

  @override
  Future<void> publishMasterManifest(List<Track> catalog) async {
    _masterManifest.clear();
    _masterManifest.addAll(catalog);
  }

  @override
  Future<int> getOrCreateDecadeSupergroup(int year) async {
    final decade = (year ~/ 10) * 10;
    return _decadeSupergroups.putIfAbsent(decade, () => -1002000000000 - decade);
  }

  @override
  Future<int> getOrCreateGenreTopic(int supergroupId, String genreOrLanguage) async {
    final key = '$supergroupId:$genreOrLanguage';
    return _genreTopics.putIfAbsent(key, () => Random().nextInt(1000) + 1);
  }

  void dispose() {
    _authStateController.close();
  }
}
