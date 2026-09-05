import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  double _cacheSizeGb = 5.0;
  
  // Accordion state
  final List<bool> _isExpanded = [false, true, false, false];

  // Provider Settings State
  List<String> _providerWaterfall = ['deezer', 'qobuz', 'tidal', 'amazon', 'ytmusic'];
  final Map<String, bool> _providerEnabled = {
    'deezer': true, 'qobuz': true, 'tidal': true, 'amazon': true, 'ytmusic': true
  };

  @override
  void initState() {
    super.initState();
    _loadProviderSettings();
  }

  Future<void> _loadProviderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedWaterfall = prefs.getStringList('provider_waterfall_priority');
    if (savedWaterfall != null && savedWaterfall.isNotEmpty) {
      setState(() {
        _providerWaterfall = savedWaterfall;
      });
    }
    setState(() {
      for (var p in _providerWaterfall) {
        _providerEnabled[p] = prefs.getBool('provider_${p}_enabled') ?? true;
      }
    });
  }

  Future<void> _saveProviderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('provider_waterfall_priority', _providerWaterfall);
    for (var entry in _providerEnabled.entries) {
      await prefs.setBool('provider_${entry.key}_enabled', entry.value);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultContractProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings & Integrations'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: ExpansionPanelList(
          expansionCallback: (int index, bool isExpanded) {
            setState(() {
              _isExpanded[index] = isExpanded;
            });
          },
          elevation: 0,
          expandedHeaderPadding: const EdgeInsets.symmetric(vertical: 8),
          dividerColor: Colors.white.withValues(alpha: 0.05),
          children: [
            // 1. Audio & Providers
            _buildExpansionPanel(
              index: 0,
              title: 'Audio Quality & Providers',
              icon: Icons.graphic_eq_rounded,
              body: Column(
                children: [
                  ListTile(
                    title: const Text('Streaming Quality', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Opus 320kbps (Fast progressive streaming)'),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () {},
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('Download Quality', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('FLAC Lossless (Original bit-perfect)'),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                    onTap: () {},
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('Provider Waterfall Priority', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${_providerWaterfall.take(3).map((p) => p.toUpperCase()).join(' > ')}...'),
                    trailing: const Icon(Icons.reorder_rounded, color: AppTheme.textMuted),
                    onTap: _showWaterfallModal,
                  ),
                ],
              ),
            ),

            // 2. Telegram Vault
            _buildExpansionPanel(
              index: 1,
              title: 'Telegram Cloud Storage',
              icon: Icons.cloud_done_rounded,
              body: StreamBuilder<VaultAuthState>(
                stream: vault.authStateStream,
                initialData: vault.currentAuthState,
                builder: (context, snapshot) {
                  final state = snapshot.data ?? VaultAuthState.unauthenticated;
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              state == VaultAuthState.authenticated ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                              color: state == VaultAuthState.authenticated ? AppTheme.secondary : AppTheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                state == VaultAuthState.authenticated
                                    ? 'Connected • Unlimited Storage Active'
                                    : 'Not Logged In • Offline Cache Only',
                                style: TextStyle(
                                  color: state == VaultAuthState.authenticated ? AppTheme.secondary : AppTheme.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (state == VaultAuthState.unauthenticated) ...[
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              hintText: '+1 234 567 8900',
                              labelText: 'Phone Number (International)',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_phoneController.text.trim().isNotEmpty) {
                                vault.sendPhoneNumber(_phoneController.text.trim());
                              }
                            },
                            child: const Text('Send Login Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ] else if (state == VaultAuthState.waitCode) ...[
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: '12345',
                              labelText: 'Enter Telegram Code',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_codeController.text.trim().isNotEmpty) {
                                vault.sendAuthCode(_codeController.text.trim());
                              }
                            },
                            child: const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ] else if (state == VaultAuthState.waitPassword) ...[
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: InputDecoration(
                              hintText: 'Enter 2FA Password',
                              labelText: 'Two-Step Verification Password',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_passwordController.text.isNotEmpty) {
                                vault.sendPassword(_passwordController.text);
                              }
                            },
                            child: const Text('Submit 2FA Password', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ] else ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              minimumSize: const Size.fromHeight(40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Disconnect Telegram Account'),
                            onPressed: () => vault.logout(),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            // 3. Storage & Cache
            _buildExpansionPanel(
              index: 2,
              title: 'Storage & Cache',
              icon: Icons.sd_storage_rounded,
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Auto-Cache Limit (LRU)', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_cacheSizeGb.toStringAsFixed(1)} GB', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Slider(
                      value: _cacheSizeGb,
                      min: 1.0,
                      max: 20.0,
                      divisions: 19,
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setState(() => _cacheSizeGb = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Audio cache cleared (pinned favorites preserved)')),
                        );
                      },
                      label: const Text('Clear Unpinned Streaming Cache'),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Desktop Companion
            _buildExpansionPanel(
              index: 3,
              title: 'SongStore Desktop Companion',
              icon: Icons.computer_rounded,
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sync your playback state, library, and settings with SongStore on Windows, macOS, or Linux via local network.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.primary,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scanning for SongStore instances...')),
                        );
                      },
                      label: const Text('Scan QR Code to Pair', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWaterfallModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'Provider Priority',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: _providerWaterfall.length,
                      itemBuilder: (context, index) {
                        final provider = _providerWaterfall[index];
                        final isEnabled = _providerEnabled[provider] ?? true;
                        return CheckboxListTile(
                          key: ValueKey(provider),
                          title: Text(
                            provider.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isEnabled ? Colors.white : AppTheme.textMuted,
                            ),
                          ),
                          value: isEnabled,
                          secondary: const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted),
                          onChanged: (val) {
                            setModalState(() {
                              _providerEnabled[provider] = val ?? false;
                            });
                            setState(() {
                              _providerEnabled[provider] = val ?? false;
                            });
                            _saveProviderSettings();
                          },
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        setModalState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = _providerWaterfall.removeAt(oldIndex);
                          _providerWaterfall.insert(newIndex, item);
                        });
                        setState(() {});
                        _saveProviderSettings();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  ExpansionPanel _buildExpansionPanel({
    required int index,
    required String title,
    required IconData icon,
    required Widget body,
  }) {
    return ExpansionPanel(
      backgroundColor: AppTheme.card,
      canTapOnHeader: true,
      headerBuilder: (context, isExpanded) {
        return ListTile(
          leading: Icon(icon, color: AppTheme.primary),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        );
      },
      body: body,
      isExpanded: _isExpanded[index],
    );
  }
}
