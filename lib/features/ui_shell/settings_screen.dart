import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _storageUsedBytes = 0;
  int _storageLimitMb = 0; // 0 = unlimited

  List<String> _providerWaterfall = ['qobuz', 'tidal', 'deezer', 'spotify', 'apple', 'amazon'];
  final Map<String, bool> _providerEnabled = {
    'qobuz': true,
    'tidal': true,
    'deezer': true,
    'spotify': true,
    'apple': true,
    'amazon': true,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWaterfall = prefs.getStringList('provider_waterfall_priority');
    if (savedWaterfall != null && savedWaterfall.isNotEmpty) {
      _providerWaterfall = savedWaterfall.where((b) => b != 'ytmusic' && b != 'youtube').toList();
    }
    for (var p in _providerWaterfall) {
      _providerEnabled[p] = prefs.getBool('provider_${p}_enabled') ?? true;
    }
    _storageLimitMb = prefs.getInt('downloads_storage_limit_mb') ?? 0;

    final downloadManager = ref.read(downloadManagerProvider);
    final usage = await downloadManager.getStorageUsageBytes();

    if (mounted) {
      setState(() {
        _storageUsedBytes = usage;
      });
    }
  }

  Future<void> _saveProviderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('provider_waterfall_priority', _providerWaterfall);
    for (var entry in _providerEnabled.entries) {
      await prefs.setBool('provider_${entry.key}_enabled', entry.value);
    }
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
    final qualityMode = ref.watch(audioQualityModeProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Audio Quality Section
          const Text(
            'AUDIO STREAMING QUALITY',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppTheme.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                RadioListTile<AudioQualityMode>(
                  title: const Text('Max Lossless (24-bit / 16-bit FLAC)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Studio Quality up to 192kHz (Qobuz / Tidal / Deezer)', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  value: AudioQualityMode.maxLossless,
                  groupValue: qualityMode,
                  activeColor: AppTheme.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(audioQualityModeProvider.notifier).state = mode;
                    }
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                RadioListTile<AudioQualityMode>(
                  title: const Text('CD Quality (16-bit / 44.1kHz FLAC)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Clean bit-perfect lossless with faster buffering', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  value: AudioQualityMode.cdQuality,
                  groupValue: qualityMode,
                  activeColor: AppTheme.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(audioQualityModeProvider.notifier).state = mode;
                    }
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                RadioListTile<AudioQualityMode>(
                  title: const Text('Adaptive Network Tier', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('FLAC on Wi-Fi, automatic 320k Opus on mobile data', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  value: AudioQualityMode.adaptive,
                  groupValue: qualityMode,
                  activeColor: AppTheme.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(audioQualityModeProvider.notifier).state = mode;
                    }
                  },
                ),
                const Divider(height: 1, color: Colors.white10),
                RadioListTile<AudioQualityMode>(
                  title: const Text('Data Saver (320kbps Opus)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Low bandwidth usage, never queries Hi-Res servers', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  value: AudioQualityMode.dataSaver,
                  groupValue: qualityMode,
                  activeColor: AppTheme.primary,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(audioQualityModeProvider.notifier).state = mode;
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Offline Downloads & Storage Section
          const Text(
            'DOWNLOADS & STORAGE',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Downloaded Files Space', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(_formatBytes(_storageUsedBytes), style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Downloads Storage Limit', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    DropdownButton<int>(
                      value: _storageLimitMb,
                      dropdownColor: AppTheme.card,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Unlimited')),
                        DropdownMenuItem(value: 1024, child: Text('1 GB')),
                        DropdownMenuItem(value: 5120, child: Text('5 GB')),
                        DropdownMenuItem(value: 10240, child: Text('10 GB')),
                        DropdownMenuItem(value: 20480, child: Text('20 GB')),
                      ],
                      onChanged: (val) async {
                        if (val != null) {
                          setState(() => _storageLimitMb = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('downloads_storage_limit_mb', val);
                        }
                      },
                    ),
                  ],
                ),
                const Divider(height: 24, color: Colors.white10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.cleaning_services_rounded, color: Colors.redAccent, size: 18),
                    label: const Text('Clear Streaming Cache (Keep Downloads)', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    onPressed: () async {
                      final acquisition = ref.read(acquisitionContractProvider);
                      await acquisition.purgeTempDirectory();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Streaming cache cleared successfully!'), backgroundColor: Colors.green),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // SpotiFLAC Multi-Source Providers
          const Text(
            'SPOTIFLAC PROVIDERS',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: AppTheme.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: _providerWaterfall.map((backend) {
                final isEnabled = _providerEnabled[backend] ?? true;
                return SwitchListTile(
                  title: Text(backend.toUpperCase(), style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    backend == 'qobuz'
                        ? '24-bit Hi-Res Studio FLAC'
                        : backend == 'tidal'
                            ? 'Hi-Res Lossless MQA/FLAC'
                            : backend == 'deezer'
                                ? '16-bit CD Quality HiFi FLAC'
                                : 'Catalog & Lossless Streaming',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
                  value: isEnabled,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (val) {
                    setState(() {
                      _providerEnabled[backend] = val;
                    });
                    _saveProviderSettings();
                  },
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
