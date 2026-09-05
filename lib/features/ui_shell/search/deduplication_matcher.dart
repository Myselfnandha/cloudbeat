import '../../../core/contracts/acquisition_contract.dart';
import '../../../core/contracts/models.dart';

class DeduplicationMatcher {
  static final RegExp _tagRegex = RegExp(
    r'\((?:feat|ft|remastered|remaster|from|ost|official|audio|video|lyrics)[^)]*\)|\[(?:feat|ft|remastered|remaster|from|ost|official|audio|video|lyrics)[^\]]*\]',
    caseSensitive: false,
  );

  static final RegExp _punctuationRegex = RegExp(r'[^\w\s]', unicode: true);
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');

  /// Searches for an existing matching track in the user's Telegram Vault.
  ///
  /// Uses a strict two-stage strategy:
  /// 1. **Primary Stage (ISRC Match):** If both tracks have valid ISRCs, exact ISRC
  ///    equality is authoritative, regardless of title or metadata formatting variations.
  /// 2. **Fallback Stage (Normalized Title + Primary Artist + Duration Proximity):**
  ///    When ISRC is missing, normalizes title & primary artist and strictly verifies that
  ///    playback duration differs by no more than 3 seconds (to prevent false matches on covers/remixes).
  static Track? findMatch(ExternalTrackResult online, List<Track> vaultTracks) {
    final onlineIsrc = online.isrc?.trim();

    // 1. Primary: ISRC match
    if (onlineIsrc != null && onlineIsrc.isNotEmpty) {
      for (final vaultTrack in vaultTracks) {
        final vaultIsrc = vaultTrack.isrc?.trim();
        if (vaultIsrc != null && vaultIsrc.isNotEmpty) {
          if (vaultIsrc.toLowerCase() == onlineIsrc.toLowerCase()) {
            return vaultTrack;
          }
        }
      }
    }

    // 2. Fallback: Normalized Title + Primary Artist + Duration Delta <= 3s
    final normOnlineTitle = normalizeTitle(online.title);
    final normOnlineArtist = normalizeArtist(online.artists.isNotEmpty ? online.artists.first : '');

    if (normOnlineTitle.isEmpty || normOnlineArtist.isEmpty) {
      return null;
    }

    for (final vaultTrack in vaultTracks) {
      final normVaultTitle = normalizeTitle(vaultTrack.title);
      final normVaultArtist = normalizeArtist(vaultTrack.artists.isNotEmpty ? vaultTrack.artists.first : '');

      if (normOnlineTitle == normVaultTitle && normOnlineArtist == normVaultArtist) {
        // Duration proximity check
        if (online.durationSeconds > 0 && vaultTrack.durationSeconds > 0) {
          final diff = (online.durationSeconds - vaultTrack.durationSeconds).abs();
          if (diff <= 3) {
            return vaultTrack;
          }
        } else {
          // If duration is missing on either, accept normalized title + artist
          return vaultTrack;
        }
      }
    }

    return null;
  }

  static bool isDuplicate(ExternalTrackResult online, List<Track> vaultTracks) {
    return findMatch(online, vaultTracks) != null;
  }

  static bool isVaulted(ExternalTrackResult online, List<Track> vaultTracks) {
    return isDuplicate(online, vaultTracks);
  }

  static String normalizeTitle(String title) {
    return title
        .replaceAll(_tagRegex, '')
        .replaceAll(_punctuationRegex, ' ')
        .replaceAll(_multiSpaceRegex, ' ')
        .trim()
        .toLowerCase();
  }

  static String normalizeArtist(String artist) {
    final primary = artist.split(RegExp(r'[,/&]|(?:\s+(?:feat|ft)\.?\s+)', caseSensitive: false)).first;
    return primary
        .replaceAll(_punctuationRegex, ' ')
        .replaceAll(_multiSpaceRegex, ' ')
        .trim()
        .toLowerCase();
  }
}
