import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/terminal_messenger.dart';
import '../widgets/terminal_widgets.dart';
import 'home_screen.dart';

String _deviceLabel(Map device) {
  for (final key in ['name', 'hostname', 'vendor']) {
    final value = device[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return 'unknown_device';
}

/// "wifi -61dBm", "LAN3" o "" si no se conoce el tipo de conexión.
String _linkLabel(Map device) {
  if (device['conn'] == 'wifi') {
    final signal = device['signal'] as num? ?? 0;
    return signal == 0 ? 'wifi' : 'wifi ${signal}dBm';
  }
  if (device['conn'] == 'eth') {
    final port = '${device['port'] ?? ''}';
    return port.isEmpty ? 'cable' : port;
  }
  return '';
}

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});

  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> with Polling {
  static const _filters = ['online', 'todos', 'nuevos'];
  Map<String, dynamic>? _data;
  String? _error;
  int _filter = 0;

  @override
  Duration get pollInterval => const Duration(seconds: 8);

  @override
  Future<void> refresh() async {
    final result = await ApiService.instance.get('/network/devices');
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _data = Map<String, dynamic>.from(result.data);
        _error = null;
      } else {
        _error = result.message;
      }
    });
  }

  List<Map<String, dynamic>> get _visible {
    final devices = [
      for (final d in (_data?['devices'] as List? ?? []))
        Map<String, dynamic>.from(d)
    ];
    return devices.where((d) {
      if (_filter == 0) return d['online'] == true;
      if (_filter == 2) return d['known'] != true;
      return true;
    }).toList();
  }

  /// Pide un escaneo nuevo y espera a que termine (hasta 25 s), en vez de
  /// mostrar la lista anterior.
  Future<void> _scan() async {
    HapticFeedback.lightImpact();
    final before = _data?['last_scan'] as num?;
    final result = await ApiService.instance.post('/network/scan');
    if (!mounted) return;
    if (!result.success) {
      TerminalMessenger.show(context, 'ERR: ${result.message}', isError: true);
      return;
    }
    setState(() => _data?['scanning'] = true);
    for (int i = 0; i < 25 && mounted; i++) {
      await Future.delayed(const Duration(seconds: 1));
      await refresh();
      final after = _data?['last_scan'] as num?;
      if (after != null && after != before && _data?['scanning'] != true) {
        return;
      }
    }
  }

  Future<void> _trustAll() async {
    final ok = await confirmAction(context,
        title: 'TRUST_ALL_DEVICES?',
        message:
            'Todos los dispositivos vistos hasta ahora se marcarán como conocidos. Solo los que aparezcan después saldrán como nuevos.',
        confirmLabel: 'TRUST');
    if (!ok) return;
    await ApiService.instance.post('/network/known-all');
    refresh();
  }

  Future<void> _open(Map<String, dynamic> device) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DeviceSheet(
          device: device, canBlock: _data?['can_block'] == true),
    );
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Center(
          child: _error == null
              ? const TerminalLoading()
              : EmptyState('error: $_error'));
    }
    final visible = _visible;
    final total = (data['devices'] as List).length;
    final unknown = data['unknown'] as int? ?? 0;
    final scanning = data['scanning'] == true;

    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionTitle('NETWORK',
              trailing: scanning
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : InkWell(
                      onTap: _scan,
                      child: const Text('scan()',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.function)),
                    )),
          if (_error != null || data['error'] != null) ...[
            TerminalMessenger.inlineBanner(
                _error != null ? 'SERVER_UNREACHABLE' : 'SCAN_ERROR',
                '${_error ?? data['error']}',
                isError: true),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                  child: _counter('${data['online']}', 'ONLINE',
                      Colors.greenAccent)),
              const SizedBox(width: 10),
              Expanded(child: _counter('$total', 'VISTOS', AppColors.function)),
              const SizedBox(width: 10),
              Expanded(
                  child: _counter('$unknown', 'NUEVOS',
                      unknown > 0 ? Colors.orangeAccent : AppColors.comment)),
            ],
          ),
          const SizedBox(height: 10),
          Panel(
            child: Column(
              children: [
                InfoRow('SUBNET', '${data['subnet'] ?? '--'}', icon: Icons.hub),
                InfoRow('GATEWAY', '${data['gateway'] ?? '--'}',
                    icon: Icons.router),
                InfoRow(
                    'SOURCE',
                    data['source'] == 'router'
                        ? 'router (panel web)'
                        : 'escaneo ARP',
                    icon: Icons.radar),
                InfoRow('LAST_SCAN', formatAgo(data['last_scan'] as num?),
                    icon: Icons.schedule),
              ],
            ),
          ),
          if (data['router'] is Map) ...[
            const SizedBox(height: 10),
            _routerPanel(data['router'] as Map),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilterBar(
                    options: _filters,
                    selected: _filter,
                    onSelected: (index) => setState(() => _filter = index)),
              ),
              if (unknown > 1)
                TextButton(
                    onPressed: _trustAll,
                    child: const Text('trust_all()',
                        style: TextStyle(fontSize: 11))),
            ],
          ),
          const SizedBox(height: 15),
          if (visible.isEmpty)
            EmptyState(_filter == 2
                ? 'ningún dispositivo nuevo'
                : 'sin dispositivos'),
          for (final device in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _card(device),
            ),
        ],
      ),
    );
  }

  Widget _routerPanel(Map router) {
    return Panel(
      child: Column(
        children: [
          InfoRow('ROUTER', '${router['model']}  ${router['firmware']}',
              icon: Icons.router),
          InfoRow(
              'LOAD',
              'cpu ${router['cpu_percent']}%  mem ${router['memory_percent']}%'
                  '  ${router['temperature']}°C',
              icon: Icons.memory),
          InfoRow('UPTIME', formatDuration(router['uptime_seconds'] as num?),
              icon: Icons.timer_outlined),
        ],
      ),
    );
  }

  Widget _counter(String value, String label, Color color) {
    return Panel(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.comment,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  IconData _icon(Map device) {
    if (device['is_gateway'] == true) return Icons.router;
    if (device['is_self'] == true) return Icons.dns;
    return switch (device['tag']) {
      'phone' => Icons.smartphone,
      'pc' => Icons.computer,
      'tv' => Icons.tv,
      'iot' => Icons.sensors,
      'console' => Icons.sports_esports,
      _ => Icons.devices_other,
    };
  }

  Widget _card(Map<String, dynamic> device) {
    final online = device['online'] == true;
    final known = device['known'] == true;
    return Panel(
      onTap: () => _open(device),
      borderColor: known ? null : Colors.orangeAccent.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(_icon(device),
              size: 20,
              color: online ? AppColors.function : AppColors.comment),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(_deviceLabel(device),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: online ? null : AppColors.comment)),
                    ),
                    const SizedBox(width: 8),
                    if (device['is_gateway'] == true)
                      const TagChip('router', AppColors.function),
                    if (device['is_self'] == true)
                      const TagChip('server', AppColors.keyword),
                    if (device['blocked'] == true)
                      const TagChip('BLOCKED', Colors.redAccent)
                    else if (!known)
                      const TagChip('NEW', Colors.orangeAccent),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                    [
                      if ('${device['ip'] ?? ''}'.isNotEmpty) device['ip'],
                      device['mac'],
                      _linkLabel(device),
                    ].where((part) => '$part'.isNotEmpty).join('  '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.comment)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusDot(online ? Colors.greenAccent : AppColors.comment),
              const SizedBox(height: 6),
              Text(online ? 'online' : formatAgo(device['last_seen'] as num?),
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.comment)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceSheet extends StatefulWidget {
  final Map<String, dynamic> device;
  final bool canBlock;
  const _DeviceSheet({required this.device, required this.canBlock});

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  static const _tags = ['phone', 'pc', 'tv', 'iot', 'console'];
  late final _nameController =
      TextEditingController(text: widget.device['name'] as String? ?? '');
  late String? _tag = widget.device['tag'] as String?;
  late bool _known = widget.device['known'] == true;
  bool _busy = false;

  String get _path => '/network/devices/${widget.device['mac']}';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await ApiService.instance.patch(_path, {
      'name': _nameController.text.trim(),
      'tag': _tag,
      'known': _known,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.success) {
      Navigator.pop(context);
    } else {
      TerminalMessenger.show(context, 'ERR: ${result.message}', isError: true);
    }
  }

  Future<void> _setBlocked(bool block) async {
    final ok = await confirmAction(context,
        title: block ? 'BLOCK_DEVICE?' : 'UNBLOCK_DEVICE?',
        message: block
            ? 'El router le negará el WiFi en todas tus redes. Si el equipo usa MAC aleatoria podría volver con otra dirección.'
            : 'El dispositivo podrá volver a conectarse al WiFi.',
        confirmLabel: block ? 'BLOCK' : 'UNBLOCK',
        danger: block);
    if (!ok) return;
    setState(() => _busy = true);
    // Son varios cambios en el router: puede tardar
    final result = await ApiService.instance
        .post('$_path/block', {'blocked': block}, 60);
    if (!mounted) return;
    setState(() => _busy = false);
    TerminalMessenger.show(
        context,
        result.success
            ? (block ? 'DEVICE_BLOCKED' : 'DEVICE_UNBLOCKED')
            : 'ERR: ${result.message}',
        isSuccess: result.success,
        isError: !result.success);
    if (result.success) Navigator.pop(context);
  }

  Future<void> _forget() async {
    final ok = await confirmAction(context,
        title: 'FORGET_DEVICE?',
        message:
            'Se borra del historial. Si sigue conectado volverá a aparecer como nuevo en el próximo escaneo.',
        confirmLabel: 'FORGET',
        danger: true);
    if (!ok) return;
    await ApiService.instance.delete(_path);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_deviceLabel(device),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            InfoRow('IP', '${device['ip']}'),
            InfoRow('MAC', '${device['mac']}'),
            InfoRow('HOSTNAME', '${device['hostname'] ?? '--'}'),
            InfoRow('VENDOR', '${device['vendor'] ?? '--'}'),
            if (_linkLabel(device).isNotEmpty)
              InfoRow('LINK', _linkLabel(device)),
            if ('${device['ssid'] ?? ''}'.isNotEmpty)
              InfoRow('SSID', '${device['ssid']}'),
            InfoRow('FIRST_SEEN', formatAgo(device['first_seen'] as num?)),
            InfoRow(
                'LAST_SEEN',
                device['online'] == true
                    ? 'online'
                    : formatAgo(device['last_seen'] as num?)),
            const SizedBox(height: 15),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'NAME',
                hintText: 'Móvil de Ana, TV salón...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilterBar(
              options: _tags,
              selected: _tag == null ? -1 : _tags.indexOf(_tag!),
              onSelected: (index) => setState(
                  () => _tag = _tag == _tags[index] ? null : _tags[index]),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _known,
              onChanged: (value) => setState(() => _known = value),
              title: const Text('TRUSTED_DEVICE',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: const Text('Conocido: deja de marcarse como nuevo',
                  style: TextStyle(fontSize: 10)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _save,
              child: const Text('save_changes()'),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (device['blocked'] == true)
              TextButton(
                onPressed: _busy ? null : () => _setBlocked(false),
                child: const Text('unblock_device()',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              )
            else if (widget.canBlock &&
                device['conn'] == 'wifi' &&
                device['is_self'] != true)
              TextButton(
                onPressed: _busy ? null : () => _setBlocked(true),
                child: const Text('block_device()',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            if (device['is_self'] != true)
              TextButton(
                onPressed: _busy ? null : _forget,
                child: const Text('forget_device()',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
