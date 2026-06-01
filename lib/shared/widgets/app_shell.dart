import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:wcpredict/core/theme/app_colors.dart';

/// The persistent app scaffold that wraps all 4 main tab screens.
///
/// Rendered by [StatefulShellRoute.indexedStack] in the router.
/// The [NavigationBar] is always visible — it never mounts per-screen.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    HapticFeedback.lightImpact();
    navigationShell.goBranch(
      index,
      // Tap the current tab → pop to root of that branch.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _AppNavBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation bar
// ---------------------------------------------------------------------------

class _AppNavBar extends StatelessWidget {
  const _AppNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _destinations = [
    _NavItem(
      label: 'Matches',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
    ),
    _NavItem(
      label: 'Live',
      icon: Icons.sensors_outlined,
      selectedIcon: Icons.sensors,
    ),
    _NavItem(
      label: 'Groups',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group,
    ),
    _NavItem(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      animationDuration: const Duration(milliseconds: 220),
      destinations: [
        for (final item in _destinations)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon:
                Icon(item.selectedIcon, color: AppColors.onPrimaryContainer),
            label: item.label,
          ),
      ],
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
