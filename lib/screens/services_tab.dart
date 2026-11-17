import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/terminal_messenger.dart';
import '../widgets/terminal_widgets.dart';
import 'home_screen.dart';

Color _stateColor(Map service) {
  if (service['running'] == true) return Colors.greenAccent;
  if (service['state'] == 'failed') return Colors.redAccent;
  return AppColors.comment;
}

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> with Polling {
  static const _filters = ['fijados', 'activos', 'todos'];
  List<Map<String, dynamic>>? _services;
  bool _allowActions = true;
  String? _error;
  int _filter = 2;
  bool _filterChosen = false;
  String _query = '';

  @override
  Duration get pollInterval => const Duration(seconds: 8);

  @override
  Future<void> refresh() async {
    final result = await ApiService.instance.get('/services', timeout: 25);
    if (!mounted) return;
    setState(() {
      if (!result.success) {
        _error = result.message;
        return;
      }
      _error = null;
      _allowActions = result.data['allow_actions'] == true;
      _services = [
        for (final s in result.data['services'] as List)
          Map<String, dynamic>.from(s)
      ];
      // Si hay servicios fijados, empezar mostrando solo esos.
      if (!_filterChosen && _services!.any((s) => s['watched'] == true)) {
        _filter = 0;
      }
    });
  }

  List<Map<String, dynamic>> get _visible {
    final query = _query.toLowerCase();
    return (_services ?? []).where((s) {
      if (_filter == 0 && s['watched'] != true) return false;
      if (_filter == 1 && s['running'] != true) return false;
      return query.isEmpty ||
          '${s['name']} ${s['unit']} ${s['description']}'
              .toLowerCase()
              .contains(query);
    }).toList();
  }

  Future<void> _open(Map<String, dynamic> service) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _ServiceSheet(service: service, allowActions: _allowActions),
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null) {
      return Center(
          child: _error == null
              ? const TerminalLoading()
              : EmptyState('error: $_error'));
    }
    final visible = _visible;
    final running = services.where((s) => s['running'] == true).length;
    final failed = services.where((s) => s['state'] == 'failed').length;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionTitle('SERVICES',
              trailing: Text(
                  '$running up${failed > 0 ? ' · $failed failed' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: failed > 0
                          ? Colors.redAccent
                          : AppColors.comment))),
          if (_error != null) ...[
            TerminalMessenger.inlineBanner('SERVER_UNREACHABLE', '$_error',
                isError: true),
            const SizedBox(height: 12),
          ],
          TextField(
            onChanged: (value) => setState(() => _query = value),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'grep ...',
              prefixIcon: Icon(Icons.search, size: 16),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilterBar(
            options: _filters,
            selected: _filter,
            onSelected: (index) => setState(() {
              _filter = index;
              _filterChosen = true;
            }),
          ),
          const SizedBox(height: 15),
          if (visible.isEmpty)
            EmptyState(_filter == 0
                ? 'sin servicios fijados: abre uno y pulsa pin()'
                : 'sin resultados'),
          for (final service in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(service),
            ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> service) {
    final running = service['running'] == true;
    final ports = (service['ports'] as List).join(',');
    final details = [
      if (service['cpu_percent'] != null) 'cpu ${service['cpu_percent']}%',
      if (service['memory_bytes'] != null)
        'mem ${formatBytes(service['memory_bytes'])}',
      if (ports.isNotEmpty) ':$ports',
      if (service['uptime_seconds'] != null)
        'up ${formatDuration(service['uptime_seconds'])}',
    ].join('  ');

    return Panel(
      onTap: () => _open(service),
      borderColor: service['state'] == 'failed'
          ? Colors.redAccent.withValues(alpha: 0.4)
          : null,
      child: Row(
        children: [
          StatusDot(_stateColor(service)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('${service['name']}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    if (service['kind'] == 'docker')
                      const TagChip('docker', AppColors.archColor),
                    if (service['watched'] == true &&
                        service['kind'] != 'docker')
                      const Icon(Icons.push_pin,
                          size: 11, color: AppColors.keyword),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                    running && details.isNotEmpty
                        ? details
                        : '${service['state']} (${service['sub_state']})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.comment)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.comment),
        ],
      ),
    );
  }
}

class _ServiceSheet extends StatefulWidget {
  final Map<String, dynamic> service;
  final bool allowActions;
  const _ServiceSheet({required this.service, required this.allowActions});

  @override
  State<_ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends State<_ServiceSheet> {
  late bool _watched = widget.service['watched'] == true;
  bool _busy = false;
  List<String>? _logs;

  String get _id => widget.service['id'] as String;

  Future<void> _action(String action) async {
    HapticFeedback.mediumImpact();
    if (action != 'start') {
      final ok = await confirmAction(context,
          title: '${action.toUpperCase()}_SERVICE?',
          message: '$action → ${widget.service['name']}',
          confirmLabel: action.toUpperCase(),
          danger: action == 'stop');
      if (!ok) return;
    }
    setState(() => _busy = true);
    final result = await ApiService.instance
        .post('/services/action', {'id': _id, 'action': action}, 65);
    if (!mounted) return;
    setState(() => _busy = false);
    TerminalMessenger.show(
        context,
        result.success
            ? '${action}_ok: ${widget.service['name']}'
            : 'ERR: ${result.message}',
        isSuccess: result.success,
        isError: !result.success);
    if (result.success) Navigator.pop(context);
  }

  Future<void> _toggleWatch() async {
    final result = await ApiService.instance
        .post('/services/watch', {'id': _id, 'watched': !_watched});
    if (!mounted) return;
    if (result.success) {
      setState(() => _watched = !_watched);
    } else {
      TerminalMessenger.show(context, 'ERR: ${result.message}', isError: true);
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _busy = true);
    final result = await ApiService.instance.get(
        '/services/logs?id=${Uri.encodeQueryComponent(_id)}&lines=150',
        timeout: 20);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _logs = result.success
          ? List<String>.from(result.data['lines'])
          : ['ERR: ${result.message}'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final running = service['running'] == true;
    final isSystemd = service['kind'] == 'systemd';
    final ports = (service['ports'] as List).join(', ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * (_logs == null ? 0.5 : 0.85),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  StatusDot(_stateColor(service)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${service['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_busy)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 4),
              Text('${service['description']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.comment)),
              const SizedBox(height: 12),
              InfoRow(isSystemd ? 'UNIT' : 'IMAGE', '${service['unit']}'),
              InfoRow('STATE', '${service['state']} (${service['sub_state']})'),
              if (ports.isNotEmpty) InfoRow('PORTS', ports),
              if (isSystemd)
                InfoRow('BOOT',
                    service['enabled'] == true ? 'enabled' : 'disabled'),
              if ((service['restarts'] as num? ?? 0) > 0)
                InfoRow('RESTARTS', '${service['restarts']}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 4,
                alignment: WrapAlignment.spaceEvenly,
                children: [
                  if (widget.allowActions && !running)
                    _button('start', Icons.play_arrow, Colors.greenAccent,
                        () => _action('start')),
                  if (widget.allowActions && running)
                    _button('restart', Icons.restart_alt, Colors.orangeAccent,
                        () => _action('restart')),
                  if (widget.allowActions && running)
                    _button('stop', Icons.stop, Colors.redAccent,
                        () => _action('stop')),
                  _button('logs', Icons.subject, AppColors.function, _loadLogs),
                  if (isSystemd)
                    _button(_watched ? 'unpin' : 'pin', Icons.push_pin,
                        AppColors.keyword, _toggleWatch),
                ],
              ),
              if (_logs != null) ...[
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        _logs!.isEmpty ? '// sin logs' : _logs!.join('\n'),
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            height: 1.4,
                            color: Color(0xFFA6E3A1)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
      String label, IconData icon, Color color, VoidCallback onPressed) {
    return TextButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text('$label()', style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
