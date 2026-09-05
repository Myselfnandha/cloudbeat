import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/contracts/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../telegram_vault/native_telegram_vault_service.dart';

class TelegramOnboardingScreen extends ConsumerStatefulWidget {
  const TelegramOnboardingScreen({super.key});

  @override
  ConsumerState<TelegramOnboardingScreen> createState() => _TelegramOnboardingScreenState();
}

class _TelegramOnboardingScreenState extends ConsumerState<TelegramOnboardingScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  int _currentStep = 0;
  bool _isLoading = false;

  StreamSubscription<VaultAuthState>? _authSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vault = ref.read(vaultContractProvider);
      _syncAuthState(vault.currentAuthState);

      _authSub = vault.authStateStream.listen((state) {
        if (mounted) {
          _syncAuthState(state);
        }
      });

      if (vault is NativeTelegramVaultService) {
        _errorSub = vault.errorStream.listen((err) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(err),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        });
      }
    });
  }

  void _syncAuthState(VaultAuthState state) {
    setState(() {
      if (state == VaultAuthState.waitPhoneNumber || state == VaultAuthState.unauthenticated) {
        _currentStep = 0;
      } else if (state == VaultAuthState.waitCode) {
        _currentStep = 1;
      } else if (state == VaultAuthState.waitPassword) {
        _currentStep = 2;
      } else if (state == VaultAuthState.authenticated) {
        _currentStep = 3;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _errorSub?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSendPhone() async {
    String phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    if (!phone.startsWith('+')) {
      phone = '+$phone';
      _phoneController.text = phone;
    }

    setState(() => _isLoading = true);
    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendPhoneNumber(phone);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);
    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendAuthCode(code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;

    setState(() => _isLoading = true);
    final vault = ref.read(vaultContractProvider);
    try {
      await vault.sendPassword(password);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 40.0, bottom: 20.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.cloud_done_rounded, size: 64, color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text(
                      'Connect to CloudBeat',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Unlimited Lossless Storage via Telegram',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primary,
                    onPrimary: Colors.black,
                  ),
                  canvasColor: AppTheme.background,
                ),
                child: Stepper(
                  currentStep: _currentStep,
                  type: StepperType.vertical,
                  onStepTapped: (step) {
                    if (step < _currentStep) {
                      setState(() => _currentStep = step);
                    }
                  },
                  controlsBuilder: (context, details) {
                    return const SizedBox.shrink();
                  },
                  steps: [
                    Step(
                      title: const Text('Phone Number', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter your Telegram phone number with country code', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: '+1 234 567 8900',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isLoading ? null : _handleSendPhone,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Send Verification Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Verification Code', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter the code sent to your Telegram app', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: '12345',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isLoading ? null : _handleSendCode,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Two-Step Verification', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Enter your cloud password (if enabled)', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 2,
                      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
                      content: Column(
                        children: [
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            style: const TextStyle(color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              filled: true,
                              fillColor: AppTheme.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isLoading ? null : _handleSendPassword,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Submit Password', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title: const Text('Vault Ready', style: TextStyle(color: AppTheme.textPrimary)),
                      subtitle: const Text('Successfully connected', style: TextStyle(color: AppTheme.textMuted)),
                      isActive: _currentStep >= 3,
                      state: _currentStep >= 3 ? StepState.complete : StepState.indexed,
                      content: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppTheme.secondary, size: 48),
                              SizedBox(height: 16),
                              Text(
                                'CloudBeat Vault Created',
                                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Taking you to your dashboard...',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
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
}
