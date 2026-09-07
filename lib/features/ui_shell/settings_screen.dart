import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import '../../core/services/streaming_cache_manager.dart';

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

  // 3 Preferences (initial ON)
  bool _cleanStreamPurity = true;
  bool _offlineCacheOnly = true;
  bool _hiRes24Bit = true;

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[SettingsScreen.initState]');
    _loadSettings();
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

    _cleanStreamPurity = prefs.getBool('clean_stream_enabled') ?? true;
    _offlineCacheOnly = prefs.getBool('offline_cache_only') ?? true;
    _hiRes24Bit = prefs.getBool('hires_24bit_enabled') ?? true;

    ref.read(cleanStreamEnabledProvider.notifier).state = _cleanStreamPurity;

    final cobaltUrl = prefs.getString('cobalt_instance_url') ?? '';
    ref.read(cobaltInstanceUrlProvider.notifier).state = cobaltUrl;

    _storageLimitMb = prefs.getInt('downloads_storage_limit_mb') ?? 0;

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

  Future<void> _savePreference(String key, bool val) async {
    AppLogger.trace('[SettingsScreen.savePreference]', 'key: $key, val: $val');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final zarzSession = ref.watch(zarzSessionManagerProvider);

    return Scaffold(
      // Spec: "Settings: background primaryContainer"
      backgroundColor: colorScheme.primaryContainer,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top header: "Settings" centered at 28sp
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
              ),

              const SizedBox(height: 20),

              // 2. "Providers" (22sp bold) + 5 switches (initial ON, no check icon on handle)
              Text(
                'Providers',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: _providers.entries.map((entry) {
                    final provider = entry.key;
                    final isEnabled = entry.value;

                    return SwitchListTile(
                      thumbIcon: const WidgetStatePropertyAll<Icon?>(null), // No check icon on handle
                      activeTrackColor: colorScheme.primary,
                      activeThumbColor: colorScheme.onPrimary,
                      title: Text(
                        provider,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        provider == 'Qobuz'
                            ? '24-bit Hi-Res Studio FLAC'
                            : provider == 'Tidal'
                                ? 'Hi-Res Lossless MQA/FLAC'
                                : provider == 'Deezer'
                                    ? '16-bit CD Quality HiFi FLAC'
                                    : 'Lossless Streaming & Catalog',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      value: isEnabled,
                      onChanged: (val) {
                        AppLogger.trace('[SettingsScreen.toggleProvider]', 'name: $provider, val: $val');
                        setState(() => _providers[provider] = val);
                        _saveProvider(provider, val);
                      },
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 24),

              // 3. "Preference" (22sp bold) + 3 switches (initial ON, no check icon on handle)
              Text(
                'Preference',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Preference 1: Clean Stream Purity
                    SwitchListTile(
                      thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
                      activeTrackColor: colorScheme.primary,
                      activeThumbColor: colorScheme.onPrimary,
                      title: Text(
                        'Clean Stream Purity',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Auto-skips intro ads, dialogue cuts, and silence via SponsorBlock & RMS detection.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      value: _cleanStreamPurity,
                      onChanged: (val) {
                        AppLogger.trace('[SettingsScreen.toggleCleanStream]', 'val: $val');
                        setState(() => _cleanStreamPurity = val);
                        ref.read(cleanStreamEnabledProvider.notifier).state = val;
                        _savePreference('clean_stream_enabled', val);
                      },
                    ),
                    Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
                    // Preference 2: Offline Cache Only
                    SwitchListTile(
                      thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
                      activeTrackColor: colorScheme.primary,
                      activeThumbColor: colorScheme.onPrimary,
                      title: Text(
                        'Offline Cache Only',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Stream exclusively from local disk cache and offline downloads when disconnected.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      value: _offlineCacheOnly,
                      onChanged: (val) {
                        AppLogger.trace('[SettingsScreen.toggleOfflineCacheOnly]', 'val: $val');
                        setState(() => _offlineCacheOnly = val);
                        _savePreference('offline_cache_only', val);
                      },
                    ),
                    Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.1)),
                    // Preference 3: Hi-Res 24-bit
                    SwitchListTile(
                      thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
                      activeTrackColor: colorScheme.primary,
                      activeThumbColor: colorScheme.onPrimary,
                      title: Text(
                        'Hi-Res 24-bit',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'Request uncompressed 24-bit studio FLAC up to 192kHz resolution.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      value: _hiRes24Bit,
                      onChanged: (val) {
                        AppLogger.trace('[SettingsScreen.toggleHiRes24Bit]', 'val: $val');
                        setState(() => _hiRes24Bit = val);
                        _savePreference('hires_24bit_enabled', val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 4. Zarz Hi-Res Lossless Tunnel Verification
              Text(
                'Hi-Res Tunnel Authentication',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
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
                                AppLogger.trace('[SettingsScreen.launchTurnstile]');
                                final launched = await zarzSession.launchTurnstileChallenge();
                                if (!launched && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not open Turnstile challenge in browser')),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.paste, size: 16),
                            label: const Text('Paste Token'),
                            onPressed: () async {
                              AppLogger.trace('[SettingsScreen.pasteZarzToken]');
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              final text = data?.text?.trim() ?? '';
                              final parsed = zarzSession.parseCallback(text);
                              if (parsed != null && parsed.grant.isNotEmpty) {
                                try {
                                  await zarzSession.completeGrant(
                                    grantToken: parsed.grant,
                                    state: parsed.state,
                                  );
                                  if (context.mounted) {
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⚡ Hi-Res Verification Complete!'),
                                        backgroundColor: Color(0xFF1DB954),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to exchange token: $e')),
                                    );
                                  }
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No grant token found in clipboard')),
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 5. Cache & Storage Management
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Downloaded Files Space',
                              style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
                          Text(_formatBytes(_storageUsedBytes),
                              style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Storage Limit', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
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
                      Divider(height: 20, color: colorScheme.outline.withValues(alpha: 0.1)),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cleaning_services_rounded, size: 16),
                          label: const Text('Clear Streaming Cache (Keep Downloads)'),
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
                    ],
                  ),
                ),
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
