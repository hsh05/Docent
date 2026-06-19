import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'stats_screen.dart';
import '../../state/game_state_notifier.dart';

class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read the current tab index
    final currentIndex = ref.watch(bottomNavProvider);

    // The screens that correspond to our tabs
    const screens = [
      HomeScreen(),
      StatsScreen(),
    ];

    return Scaffold(
      // IndexedStack preserves the state of the screens when switching tabs
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) {
            // Update the Riverpod state when a tab is tapped
            ref.read(bottomNavProvider.notifier).state = index;
          },
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.mic_none),
              selectedIcon: Icon(Icons.mic),
              label: 'Study',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}