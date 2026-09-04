// ignore_for_file: experimental_member_use
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../../core/contracts/vault_contract.dart';

class TelegramStreamAudioSource extends StreamAudioSource {
  final String fileId;
  final int totalBytes;
  final VaultContract vault;
  final String contentType;

  TelegramStreamAudioSource({
    required this.fileId,
    required this.totalBytes,
    required this.vault,
    this.contentType = 'audio/ogg',
  }) : super(tag: fileId);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= totalBytes;
    final contentLength = end - start;

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: totalBytes,
      contentLength: contentLength,
      offset: start,
      stream: _streamChunks(start, contentLength),
      contentType: contentType,
    );
  }

  Stream<List<int>> _streamChunks(int startOffset, int length) async* {
    const chunkSize = 64 * 1024; // 64KB chunk request
    int currentOffset = startOffset;
    int remaining = length;

    while (remaining > 0) {
      final requestLen = remaining > chunkSize ? chunkSize : remaining;
      final chunk = await vault.streamChunk(
        fileId: fileId,
        offset: currentOffset,
        length: requestLen,
      );
      yield chunk;
      currentOffset += requestLen;
      remaining -= requestLen;
    }
  }
}
