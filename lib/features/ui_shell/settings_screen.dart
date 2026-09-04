import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

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
        title: const Text('Settings & Cloud Vault'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Telegram Cloud Vault Authentication Section
          const Text(
            'TELEGRAM CLOUD STORAGE',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          StreamBuilder<VaultAuthState>(
            stream: vault.authStateStream,
            initialData: vault.currentAuthState,
            builder: (context, snapshot) {
              final state = snapshot.data ?? VaultAuthState.unauthenticated;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: state == VaultAuthState.authenticated
                        ? AppTheme.secondary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state == VaultAuthState.authenticated
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_queue_rounded,
                          color: state == VaultAuthState.authenticated
                              ? AppTheme.secondary
                              : AppTheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TDLib Cloud Connection',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              state == VaultAuthState.authenticated
                                  ? 'Connected • Unlimited Storage Active'
                                  : 'Not Logged In • Offline Cache Only',
                              style: TextStyle(
                                color: state == VaultAuthState.authenticated
                                    ? AppTheme.secondary
                                    : AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
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

          const SizedBox(height: 28),

          // Audio Quality Settings
          const Text(
            'AUDIO QUALITY',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
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
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Offline Storage & Cache Manager
          const Text(
            'OFFLINE STORAGE & CACHE',
            style: TextStyle(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(16),
            ),
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
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Audio cache cleared (pinned favorites preserved)')),
                    );
                  },
                  child: const Text('Clear Unpinned Streaming Cache'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
