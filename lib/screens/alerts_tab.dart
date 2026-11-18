import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';
import '../widgets/terminal_widgets.dart';
import 'home_screen.dart';

class AlertsTab extends StatefulWidget {
  final VoidCallback onRead;
  const AlertsTab({super.key, required this.onRead});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> with Polling {
  List<Map<String, dynamic>>? _events;
  String? _error;

  @override
  Duration get pollInterval => const Duration(seconds: 15);

  @override
  Future<void> refresh() async {
    final result = await ApiService.instance.get('/events?limit=200');
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _events = [
          for (final e in result.data['events'] as List)
            Map<String, dynamic>.from(e)
        ];
        _error = null;
      } else {
        _error = result.message;
      }
    });
    if (result.success && (result.data['unread'] as int? ?? 0) > 0) {
      // Abrir la pestaña cuenta como leer las alertas.
      final read = await ApiService.instance.post('/events/read');
      if (read.success && mounted) widget.onRead();
    }
  }

  (IconData, Color) _style(String type) => switch (type) {
        'new_device' => (Icons.devices_other, Colors.orangeAccent),
        'service_down' => (Icons.error_outline, Colors.redAccent),
        'service_up' => (Icons.check_circle_outline, Colors.greenAccent),
        'auth' => (Icons.lock_outline, Colors.redAccent),
        'power' => (Icons.power_settings_new, Colors.orangeAccent),
        'block' => (Icons.block, Colors.redAccent),
        'tv' => (Icons.tv, AppColors.function),
        _ => (Icons.info_outline, AppColors.function),
      };

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (events == null) {
      return Center(
          child: _error == null
              ? const TerminalLoading()
              : EmptyState('error: $_error'));
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionTitle('EVENT_LOG'),
          if (events.isEmpty) const EmptyState('sin eventos'),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(event),
            ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> event) {
    final (icon, color) = _style('${event['type']}');
    final unread = event['read'] == 0;
    return Panel(
      borderColor: unread ? color.withValues(alpha: 0.4) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${event['message']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal)),
                const SizedBox(height: 4),
                Text(
                    '${'${event['type']}'.toUpperCase()} · ${formatAgo(event['ts'] as num?)}',
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.comment)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
