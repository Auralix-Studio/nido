import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/theme_manager.dart';
import '../services/api_service.dart';
import 'alerts_tab.dart';
import 'login_screen.dart';
import 'network_tab.dart';
import 'server_tab.dart';
import 'services_tab.dart';
import 'tv_tab.dart';
import 'setup_screen.dart';

/// Refresco periódico mientras la pestaña está en pantalla.
mixin Polling<T extends StatefulWidget> on State<T> {
  Duration get pollInterval;
  Future<void> refresh();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    refresh();
    _pollTimer = Timer.periodic(pollInterval, (_) => refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with Polling {
  int _tab = 0;
  int _unread = 0;

  @override
  Duration get pollInterval => const Duration(seconds: 20);

  @override
  Future<void> refresh() async {
    final result = await ApiService.instance.get('/events?limit=1');
    if (mounted && result.success) {
      setState(() => _unread = result.data['unread'] as int? ?? 0);
    }
  }

  Future<void> _logout() async {
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text('>_ nido',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.keyword : AppColors.primaryLight)),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Tema',
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 18),
            onPressed: () => ThemeManager.instance.toggleTheme(!isDark),
          ),
          IconButton(
            tooltip: 'Conexión',
            icon: const Icon(Icons.settings_ethernet, size: 18),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SetupScreen())),
          ),
          IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 18)),
        ],
      ),
      body: switch (_tab) {
        0 => const ServerTab(),
        1 => const ServicesTab(),
        2 => const NetworkTab(),
        3 => const TvTab(),
        _ => AlertsTab(onRead: () => setState(() => _unread = 0)),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dns_outlined), label: 'server'),
          const NavigationDestination(
              icon: Icon(Icons.widgets_outlined), label: 'services'),
          const NavigationDestination(
              icon: Icon(Icons.lan_outlined), label: 'network'),
          const NavigationDestination(
              icon: Icon(Icons.tv_outlined), label: 'tv'),
          NavigationDestination(
              icon: Badge(
                  isLabelVisible: _unread > 0,
                  label: Text('$_unread'),
                  child: const Icon(Icons.notifications_none)),
              label: 'alerts'),
        ],
      ),
    );
  }
}
