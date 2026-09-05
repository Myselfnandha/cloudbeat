import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/contracts/models.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/ui_shell/main_navigation_shell.dart';
import 'features/ui_shell/telegram_onboarding_screen.dart';
import 'core/workers/background_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background tasks
  await BackgroundWorkerManager.initialize();
  await BackgroundWorkerManager.registerDailyMaintenance();

  runApp(
    const ProviderScope(
      child: CloudBeatApp(),
    ),
  );
}

class CloudBeatApp extends ConsumerWidget {
  const CloudBeatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultContractProvider);

    return MaterialApp(
      title: 'CloudBeat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: StreamBuilder<VaultAuthState>(
        stream: vault.authStateStream,
        initialData: vault.currentAuthState,
        builder: (context, snapshot) {
          final authState = snapshot.data ?? VaultAuthState.unauthenticated;
          if (authState == VaultAuthState.authenticated) {
            return const MainNavigationShell();
          }
          return const TelegramOnboardingScreen();
        },
      ),
    );
  }
}
