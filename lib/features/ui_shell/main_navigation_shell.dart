import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/services/app_logger.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'mini_player.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Global provider for current navigation tab index
final mainNavigationTabProvider = StateProvider<int>((ref) => 0);

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    AppLogger.trace('[MainNavigationShell.initState]');
    _initDeepLinks();
  }

  void _initDeepLinks() {
    AppLogger.trace('[MainNavigationShell._initDeepLinks]');
    _appLinks = AppLinks();

    // Check cold-start initial deep link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleIncomingUri(uri);
      }
    }).catchError((e) {
      AppLogger.trace('[MainNavigationShell.getInitialLink.error]', 'error: $e');
    });

    // Listen to foreground/background resume deep link stream
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingUri(uri);
    });
  }

  Future<void> _handleIncomingUri(Uri uri) async {
    AppLogger.trace('[MainNavigationShell._handleIncomingUri]', 'uri: $uri');
    final zarz = ref.read(zarzSessionManagerProvider);
    final parsed = zarz.parseCallback(uri.toString());
    if (parsed != null && parsed.grant.isNotEmpty) {
      try {
        await zarz.completeGrant(
          grantToken: parsed.grant,
          state: parsed.state,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚡ Hi-Res Streaming Verified!'),
              backgroundColor: Color(0xFF1DB954),
            ),
          );
        }
      } catch (e, st) {
        AppLogger.e('MainNavigationShell', 'deep link grant exchange failed', e, st);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    AppLogger.trace('[MainNavigationShell.dispose]');
    _linkSubscription?.cancel();
    super.dispose();
  }

  final _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mainNavigationTabProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: Stack(
        children: [
          // Animated tab transition with M3 Expressive motion
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOutCubic,
              switchOutCurve: Curves.easeInOutCubic,
              transitionBuilder: (child, animation) {
                final key = child.key as ValueKey<int>?;
                final index = key?.value ?? 0;
                if (index == 0) {
                  // Home: slide in from left
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-1.0, 0.0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                } else if (index == 3) {
                  // Settings: slide in from right
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                } else {
                  // Search & Library: fade
                  return FadeTransition(
                    opacity: animation,
                    child: child,
                  );
                }
              },
              child: KeyedSubtree(
                key: ValueKey<int>(currentIndex),
                child: _screens[currentIndex],
              ),
            ),
          ),

          // Persistent 380×60dp MiniPlayer floating above bottom navigation
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 80,
        elevation: 0,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          AppLogger.trace('[MainNavigationShell.switchTab]', 'from: $_previousIndex to: $index');
          _previousIndex = currentIndex;
          ref.read(mainNavigationTabProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
