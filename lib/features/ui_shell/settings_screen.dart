import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/streaming_cache_manager.dart';
import '../../core/session/zarz_session_manager.dart';
import 'zarz_turnstile_sheet.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _storageUsedBytes = 0;
  int _storageLimitMb = 0; // 0 = unlimited

  // 5 Providers (initial ON)
  final Map<String, bool> _providers = {
    'Spotify': true,
    'Qobuz': true,
    'Tidal': true,
    'Deezer': true,
    'Apple': true,
  };

  // Audio Engine settings
  String _audioQuality = 'hires';
  bool _gapless = true;
  double _crossfadeDuration = 0.0;
  bool _volumeNorm = true;
  bool _cleanStreamPurity = true;
  bool _hiRes24Bit = true;

  // Network & Downloads
  bool _downloadOnWifi = false;
  String _downloadQuality = 'match';
  bool _offlineCacheOnly = false;
  final TextEditingController _cobaltController = TextEditingController();

  // Appearance
  String _playerBgStyle = 'meshGradient';
  bool _oledBlack = false;
  bool _miniPlayerProgressBar = true;

  // Lyrics Engine
  String _preferredLyricsProvider = 'paxsenix';
  bool _lyricsWaterfall = true;
  bool _wordGlowEnabled = true;
  bool _vocalBadgesEnabled = true;
  double _lyricsTextScale = 1.0;

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[SettingsScreen.initState]');
    _loadSettings();
  }

  @override
  void dispose() {
    _cobaltController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    AppLogger.trace('[SettingsScreen._loadSettings]');
    final prefs = await SharedPreferences.getInstance();

    for (final p in _providers.keys) {
      final saved = prefs.getBool('provider_${p.toLowerCase()}_enabled');
      if (saved != null) {
        _providers[p] = saved;
      }
    }

    _audioQuality = prefs.getString('audio_quality_preset') ?? 'hires';
    _gapless = prefs.getBool('audio_gapless_enabled') ?? true;
    _crossfadeDuration = prefs.getDouble('audio_crossfade_duration') ?? 0.0;
    _volumeNorm = prefs.getBool('audio_volume_norm') ?? true;
    _cleanStreamPurity = prefs.getBool('clean_stream_enabled') ?? true;
    _hiRes24Bit = prefs.getBool('hires_24bit_enabled') ?? true;

    _downloadOnWifi = prefs.getBool('download_on_wifi_only') ?? false;
    _downloadQuality = prefs.getString('download_quality_preset') ?? 'match';
    _offlineCacheOnly = prefs.getBool('offline_cache_only') ?? false;
    _cobaltController.text = prefs.getString('cobalt_instance_url') ?? '';

    _playerBgStyle = prefs.getString('player_bg_style') ?? 'meshGradient';
    _oledBlack = prefs.getBool('oled_pure_black') ?? false;
    _miniPlayerProgressBar = prefs.getBool('miniplayer_progress_bar') ?? true;

    _preferredLyricsProvider = prefs.getString('preferred_lyrics_provider') ?? 'paxsenix';
    _lyricsWaterfall = prefs.getBool('lyrics_waterfall_enabled') ?? true;
    _wordGlowEnabled = prefs.getBool('lyrics_word_glow_enabled') ?? true;
    _vocalBadgesEnabled = prefs.getBool('lyrics_vocal_badges_enabled') ?? true;
    _lyricsTextScale = prefs.getDouble('lyrics_text_scale') ?? 1.0;

    _storageLimitMb = prefs.getInt('downloads_storage_limit_mb') ?? 0;

    // Sync Riverpod state
    ref.read(cleanStreamEnabledProvider.notifier).state = _cleanStreamPurity;
    ref.read(playerBackgroundStyleProvider.notifier).state = _playerBgStyle;
    ref.read(cobaltInstanceUrlProvider.notifier).state = _cobaltController.text;
    ref.read(downloadOnWifiOnlyProvider.notifier).state = _downloadOnWifi;
    ref.read(oledPureBlackProvider.notifier).state = _oledBlack;
    ref.read(miniPlayerProgressBarProvider.notifier).state = _miniPlayerProgressBar;
    ref.read(gaplessPlaybackProvider.notifier).state = _gapless;
    ref.read(crossfadeDurationSecondsProvider.notifier).state = _crossfadeDuration;
    ref.read(volumeNormalizationProvider.notifier).state = _volumeNorm;
    ref.read(lyricsTextScaleProvider.notifier).state = _lyricsTextScale;

    final downloadManager = ref.read(downloadManagerProvider);
    final usage = await downloadManager.getStorageUsageBytes();

    if (mounted) {
      setState(() {
        _storageUsedBytes = usage;
      });
    }
  }

  Future<void> _saveProvider(String name, bool val) async {
    AppLogger.trace('[SettingsScreen.saveProvider]', 'name: $name, val: $val');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('provider_${name.toLowerCase()}_enabled', val);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  Widget _buildSwitchListTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
      activeTrackColor: colorScheme.primary,
      activeThumbColor: colorScheme.onPrimary,
      inactiveTrackColor: colorScheme.surfaceContainerHighest,
      inactiveThumbColor: colorScheme.outline,
      title: Text(
        title,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(icon, color: colorScheme.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  void _showSmartPasteDialog(BuildContext context, ZarzSessionManager zarzSession) {
    final colorScheme = Theme.of(context).colorScheme;
    final textController = TextEditingController();
    String? localError;
    bool isExchanging = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 10),
              Text('Enter Session Grant', style: TextStyle(color: colorScheme.onSurface, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paste the grant token, full callback URL, or JSON response from Zarz Turnstile:',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 3,
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'grnt_... or cloudbeat://session-grant?grant=...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainer,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.content_paste_rounded, size: 16),
                      label: const Text('Paste Clipboard'),
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        final text = data?.text?.trim() ?? '';
                        if (text.isNotEmpty) {
                          setDialogState(() {
                            textController.text = text;
                            localError = null;
                          });
                        }
                      },
                    ),
                  ],
                ),
                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      localError!,
                      style: TextStyle(color: colorScheme.error, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isExchanging
                  ? null
                  : () async {
                      final input = textController.text.trim();
                      final parsed = zarzSession.parseCallback(input);
                      if (parsed == null || parsed.grant.isEmpty) {
                        setDialogState(() => localError = 'Could not find a valid grant token in input.');
                        return;
                      }

                      setDialogState(() {
                        isExchanging = true;
                        localError = null;
                      });

                      try {
                        await zarzSession.completeGrant(
                          grantToken: parsed.grant,
                          state: parsed.state,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚡ Hi-Res Verification Complete!'),
                              backgroundColor: Color(0xFF1DB954),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          isExchanging = false;
                          localError = 'Exchange failed: $e';
                        });
                      }
                    },
              child: isExchanging
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Verify Token'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final zarzSession = ref.watch(zarzSessionManagerProvider);

    return Scaffold(
      backgroundColor: colorScheme.primaryContainer,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-Left aligned "Settings" heading
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 16),
                child: Text(
                  'Settings',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ),

              // CARD 1: Providers
              _buildCard(
                context: context,
                title: 'Providers',
                icon: Icons.source_rounded,
                children: _providers.entries.map((entry) {
                  final provider = entry.key;
                  final isEnabled = entry.value;

                  return _buildSwitchListTile(
                    context: context,
                    title: provider,
                    subtitle: provider == 'Qobuz'
                        ? '24-bit Hi-Res Studio FLAC'
                        : provider == 'Tidal'
                            ? 'Hi-Res Lossless MQA/FLAC'
                            : provider == 'Deezer'
                                ? '16-bit CD Quality HiFi FLAC'
                                : 'Lossless Streaming & Catalog',
                    value: isEnabled,
                    onChanged: (val) {
                      AppLogger.trace('[SettingsScreen.toggleProvider]', 'name: $provider, val: $val');
                      setState(() => _providers[provider] = val);
                      _saveProvider(provider, val);
                    },
                  );
                }).toList(),
              ),

              // CARD 2: Preference (Audio & Playback Engine)
              _buildCard(
                context: context,
                title: 'Preference',
                icon: Icons.graphic_eq_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _audioQuality,
                      decoration: InputDecoration(
                        labelText: 'Streaming Quality',
                        filled: true,
                        fillColor: colorScheme.surfaceContainer,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      items: const [
                        DropdownMenuItem(value: 'hires', child: Text('Hi-Res 24-bit / 192kHz Master')),
                        DropdownMenuItem(value: 'flac', child: Text('Lossless CD FLAC 16-bit / 44.1kHz')),
                        DropdownMenuItem(value: 'high', child: Text('High Quality 320kbps MP3/AAC')),
                        DropdownMenuItem(value: 'saver', child: Text('Data Saver 160kbps Opus')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        setState(() => _audioQuality = val);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('audio_quality_preset', val);
                      },
                    ),
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Clean Stream Purity',
                    subtitle: 'Auto-skip dialogue, sponsor ads, and silence via SponsorBlock.',
                    value: _cleanStreamPurity,
                    onChanged: (val) async {
                      setState(() => _cleanStreamPurity = val);
                      ref.read(cleanStreamEnabledProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('clean_stream_enabled', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Hi-Res 24-bit Mode',
                    subtitle: 'Request 24-bit studio FLAC streams when available.',
                    value: _hiRes24Bit,
                    onChanged: (val) async {
                      setState(() => _hiRes24Bit = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hires_24bit_enabled', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Gapless Playback',
                    subtitle: 'Seamless transitions between continuous album tracks.',
                    value: _gapless,
                    onChanged: (val) async {
                      setState(() => _gapless = val);
                      ref.read(gaplessPlaybackProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('audio_gapless_enabled', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Volume Normalization (ReplayGain)',
                    subtitle: 'Balances loudness across different tracks and albums.',
                    value: _volumeNorm,
                    onChanged: (val) async {
                      setState(() => _volumeNorm = val);
                      ref.read(volumeNormalizationProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('audio_volume_norm', val);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Crossfade Duration',
                                style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('${_crossfadeDuration.toStringAsFixed(1)}s',
                                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Slider(
                          value: _crossfadeDuration,
                          min: 0.0,
                          max: 12.0,
                          divisions: 24,
                          activeColor: colorScheme.primary,
                          onChanged: (val) async {
                            setState(() => _crossfadeDuration = val);
                            ref.read(crossfadeDurationSecondsProvider.notifier).state = val;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setDouble('audio_crossfade_duration', val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // CARD 3: Hi-Res Tunnel Authentication (Zarz V2)
              _buildCard(
                context: context,
                title: 'Hi-Res Tunnel Authentication',
                icon: Icons.shield_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Zarz V2 Tunnel',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: zarzSession.hasValidSession
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                zarzSession.hasValidSession ? 'VERIFIED' : 'ACTION REQUIRED',
                                style: TextStyle(
                                  color: zarzSession.hasValidSession ? Colors.green : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          zarzSession.hasValidSession
                              ? 'Authenticated for Qobuz 24-bit Hi-Res and Tidal Master streaming.'
                              : 'Solve Turnstile challenge to unlock free 24-bit FLAC streams.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.shield_outlined, size: 16),
                                label: Text(zarzSession.hasValidSession ? 'Re-verify' : 'Verify (Turnstile)'),
                                onPressed: () async {
                                  AppLogger.trace('[SettingsScreen.openTurnstileModal]');
                                  final success = await ZarzTurnstileSheet.show(context);
                                  if (success == true && context.mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⚡ Hi-Res Verification Complete!'),
                                        backgroundColor: Color(0xFF1DB954),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.paste_rounded, size: 16),
                              label: const Text('Paste Token'),
                              onPressed: () => _showSmartPasteDialog(context, zarzSession),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // CARD 4: Network & Downloads
              _buildCard(
                context: context,
                title: 'Network & Downloads',
                icon: Icons.download_rounded,
                children: [
                  _buildSwitchListTile(
                    context: context,
                    title: 'Download on Wi-Fi Only',
                    subtitle: 'Prevents large FLAC downloads over mobile cellular data.',
                    value: _downloadOnWifi,
                    onChanged: (val) async {
                      setState(() => _downloadOnWifi = val);
                      ref.read(downloadOnWifiOnlyProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('download_on_wifi_only', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Offline Cache Only',
                    subtitle: 'Stream exclusively from local disk cache and downloaded files.',
                    value: _offlineCacheOnly,
                    onChanged: (val) async {
                      setState(() => _offlineCacheOnly = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('offline_cache_only', val);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _downloadQuality,
                      decoration: InputDecoration(
                        labelText: 'Download Audio Quality',
                        filled: true,
                        fillColor: colorScheme.surfaceContainer,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      items: const [
                        DropdownMenuItem(value: 'match', child: Text('Match Streaming Quality')),
                        DropdownMenuItem(value: 'force24', child: Text('Force 24-bit Master FLAC')),
                        DropdownMenuItem(value: 'force16', child: Text('Force 16-bit CD FLAC')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        setState(() => _downloadQuality = val);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('download_quality_preset', val);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _cobaltController,
                      decoration: InputDecoration(
                        labelText: 'Custom Cobalt Instance URL',
                        hintText: 'https://cobalt.api.example.com',
                        filled: true,
                        fillColor: colorScheme.surfaceContainer,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check_rounded),
                          onPressed: () async {
                            final url = _cobaltController.text.trim();
                            ref.read(cobaltInstanceUrlProvider.notifier).state = url;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('cobalt_instance_url', url);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cobalt instance URL saved!')),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Storage Allocation Limit',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                        DropdownButton<int>(
                          value: _storageLimitMb,
                          dropdownColor: colorScheme.surfaceContainerHigh,
                          underline: const SizedBox.shrink(),
                          style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Unlimited')),
                            DropdownMenuItem(value: 1024, child: Text('1 GB')),
                            DropdownMenuItem(value: 5120, child: Text('5 GB')),
                            DropdownMenuItem(value: 10240, child: Text('10 GB')),
                            DropdownMenuItem(value: 20480, child: Text('20 GB')),
                          ],
                          onChanged: (val) async {
                            if (val != null) {
                              AppLogger.trace('[SettingsScreen.setStorageLimit]', 'val: $val');
                              setState(() => _storageLimitMb = val);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('downloads_storage_limit_mb', val);
                              await StreamingCacheManager.instance.setCacheLimitMb(val > 0 ? val : 102400);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // CARD 5: Interface & Appearance
              _buildCard(
                context: context,
                title: 'Interface & Appearance',
                icon: Icons.palette_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _playerBgStyle,
                      decoration: InputDecoration(
                        labelText: 'Now Playing Background',
                        filled: true,
                        fillColor: colorScheme.surfaceContainer,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      items: const [
                        DropdownMenuItem(value: 'meshGradient', child: Text('Dynamic Mesh Gradient Blur')),
                        DropdownMenuItem(value: 'solidDynamic', child: Text('Solid Dynamic M3 Color')),
                        DropdownMenuItem(value: 'darkGlass', child: Text('Dark Glass (Onyx)')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        setState(() => _playerBgStyle = val);
                        ref.read(playerBackgroundStyleProvider.notifier).state = val;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('player_bg_style', val);
                      },
                    ),
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'OLED Pure Black Mode',
                    subtitle: 'Uses true black #000000 for maximum battery efficiency.',
                    value: _oledBlack,
                    onChanged: (val) async {
                      setState(() => _oledBlack = val);
                      ref.read(oledPureBlackProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('oled_pure_black', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'MiniPlayer Progress Bar',
                    subtitle: 'Shows thin playback progress line on the floating miniplayer.',
                    value: _miniPlayerProgressBar,
                    onChanged: (val) async {
                      setState(() => _miniPlayerProgressBar = val);
                      ref.read(miniPlayerProgressBarProvider.notifier).state = val;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('miniplayer_progress_bar', val);
                    },
                  ),
                ],
              ),

              // CARD 6: Lyrics & Karaoke Engine
              _buildCard(
                context: context,
                title: 'Lyrics & Karaoke Engine',
                icon: Icons.mic_external_on_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: DropdownButtonFormField<String>(
                      value: _preferredLyricsProvider,
                      decoration: InputDecoration(
                        labelText: 'Preferred Lyrics Provider',
                        filled: true,
                        fillColor: colorScheme.surfaceContainer,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      dropdownColor: colorScheme.surfaceContainerHigh,
                      items: const [
                        DropdownMenuItem(value: 'paxsenix', child: Text('Paxsenix (Apple Music Syllables)')),
                        DropdownMenuItem(value: 'betterLyrics', child: Text('BetterLyrics (TTML)')),
                        DropdownMenuItem(value: 'youlyPlus', child: Text('YouLyPlus (Multi-Server Syllables)')),
                        DropdownMenuItem(value: 'lrclib', child: Text('LRCLIB (Verified Synced)')),
                        DropdownMenuItem(value: 'simpmusic', child: Text('SimpMusic (YouTube Matched)')),
                        DropdownMenuItem(value: 'kugou', child: Text('KuGou (Asian/C-Pop/Anime)')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        setState(() => _preferredLyricsProvider = val);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('preferred_lyrics_provider', val);
                      },
                    ),
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Adaptive Waterfall Fallback',
                    subtitle: 'Automatically queries remaining 5 lyrics engines on miss.',
                    value: _lyricsWaterfall,
                    onChanged: (val) async {
                      setState(() => _lyricsWaterfall = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('lyrics_waterfall_enabled', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Apple-Style Word Glow',
                    subtitle: 'Animate individual words with flowing karaoke glow.',
                    value: _wordGlowEnabled,
                    onChanged: (val) async {
                      setState(() => _wordGlowEnabled = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('lyrics_word_glow_enabled', val);
                    },
                  ),
                  _buildSwitchListTile(
                    context: context,
                    title: 'Vocal Separation Badges',
                    subtitle: 'Distinguish background vocals {bg} and multi-singer duets (V1/V2).',
                    value: _vocalBadgesEnabled,
                    onChanged: (val) async {
                      setState(() => _vocalBadgesEnabled = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('lyrics_vocal_badges_enabled', val);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Lyrics Text Size Scale',
                                style: TextStyle(color: colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('${(_lyricsTextScale * 100).toInt()}%',
                                style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Slider(
                          value: _lyricsTextScale,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          activeColor: colorScheme.primary,
                          onChanged: (val) async {
                            setState(() => _lyricsTextScale = val);
                            ref.read(lyricsTextScaleProvider.notifier).state = val;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setDouble('lyrics_text_scale', val);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                      label: const Text('Clear Lyrics Cache'),
                      onPressed: () {
                        ref.read(unifiedLyricsServiceProvider).clearCache();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lyrics cache cleared!'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ),
                ],
              ),

              // CARD 7: Backup, Library & Storage
              _buildCard(
                context: context,
                title: 'Backup, Library & Storage',
                icon: Icons.inventory_2_rounded,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Downloaded Files Space',
                            style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(_formatBytes(_storageUsedBytes),
                            style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.file_upload_outlined, size: 16),
                            label: const Text('Export Library'),
                            onPressed: () async {
                              final catalog = ref.read(catalogContractProvider);
                              final favs = await catalog.getFavorites();
                              final jsonStr = jsonEncode({
                                'version': 1,
                                'exportedAt': DateTime.now().toIso8601String(),
                                'favorites': favs.map((t) => t.toMap()).toList(),
                              });
                              await Clipboard.setData(ClipboardData(text: jsonStr));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Library JSON exported to clipboard!')),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.file_download_outlined, size: 16),
                            label: const Text('Import Library'),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Select a valid CloudBeat library JSON backup.')),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                        label: const Text('Clear Streaming Temp Cache'),
                        onPressed: () async {
                          AppLogger.trace('[SettingsScreen.clearCache]');
                          final acquisition = ref.read(acquisitionContractProvider);
                          await acquisition.purgeTempDirectory();
                          await StreamingCacheManager.instance.clearCache();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Streaming cache cleared successfully!')),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text('Reset All Settings to Default'),
                        style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: colorScheme.surfaceContainerHigh,
                              title: const Text('Reset All Settings?'),
                              content: const Text('This will reset your preferences to default values.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.error,
                                    foregroundColor: colorScheme.onError,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Reset'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();
                            await _loadSettings();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('All settings reset to defaults.')),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom padding for 60dp MiniPlayer
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
