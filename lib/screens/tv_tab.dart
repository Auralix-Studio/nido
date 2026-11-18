import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/terminal_messenger.dart';
import '../widgets/terminal_widgets.dart';
import 'home_screen.dart';

/// Mando a distancia de la TV LG (webOS) a través de Nido.
class TvTab extends StatefulWidget {
  const TvTab({super.key});

  @override
  State<TvTab> createState() => _TvTabState();
}

class _TvTabState extends State<TvTab> with Polling {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _tvs = [];
  String? _mac; // TV elegida
  List<Map<String, dynamic>> _apps = [];
  String? _error;
  bool _busy = false;
  double? _volumeDrag;
  Timer? _volumeDebounce;

  @override
  Duration get pollInterval => const Duration(seconds: 10);

  @override
  void dispose() {
    _volumeDebounce?.cancel();
    super.dispose();
  }

  String get _macQuery =>
      _mac == null ? '' : '?mac=${Uri.encodeQueryComponent(_mac!)}';

  Future<void> _loadTvs() async {
    final result = await ApiService.instance.get('/tv/list', timeout: 20);
    if (!mounted || !result.success) return;
    final tvs = [
      for (final tv in result.data['tvs'] as List? ?? [])
        Map<String, dynamic>.from(tv)
    ];
    setState(() {
      _tvs = tvs;
      final stillThere = tvs.any((tv) => tv['mac'] == _mac);
      if (!stillThere) {
        // Por defecto, la primera compatible
        final lg = tvs.where((tv) => tv['kind'] == 'lg');
        _mac = (lg.isNotEmpty
            ? lg.first
            : (tvs.isNotEmpty ? tvs.first : null))?['mac'];
      }
    });
  }

  void _select(String mac) {
    setState(() {
      _mac = mac;
      _status = null;
      _apps = [];
    });
    refresh();
  }

  @override
  Future<void> refresh() async {
    if (_tvs.isEmpty) await _loadTvs();
    final result =
        await ApiService.instance.get('/tv/status$_macQuery', timeout: 20);
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _status = Map<String, dynamic>.from(result.data);
        _error = null;
      } else {
        _error = result.message;
      }
    });
    if (_apps.isEmpty &&
        _status?['paired'] == true &&
        _status?['kind'] == 'lg' &&
        _status?['error'] == null) {
      _loadApps();
    }
  }

  Future<void> _loadApps() async {
    final result =
        await ApiService.instance.get('/tv/apps$_macQuery', timeout: 20);
    if (!mounted || !result.success) return;
    setState(() => _apps = [
          for (final app in result.data['apps'] as List? ?? [])
            Map<String, dynamic>.from(app)
        ]);
  }

  Future<void> _send(String action, [String value = '']) async {
    HapticFeedback.lightImpact();
    final result = await ApiService.instance.post('/tv/command',
        {'mac': _mac ?? '', 'action': action, 'value': value}, 20);
    if (!mounted) return;
    if (!result.success) {
      TerminalMessenger.show(context, 'ERR: ${result.message}', isError: true);
    } else if (action == 'power_on') {
      TerminalMessenger.show(context, 'POWER_ON_SENT', isSuccess: true);
      Future.delayed(const Duration(seconds: 8), refresh);
    } else if (action.startsWith('volume') || action == 'mute') {
      refresh();
    }
  }

  Future<void> _pair() async {
    setState(() => _busy = true);
    TerminalMessenger.show(context, 'ACEPTA EL AVISO EN LA PANTALLA DE LA TV');
    final result =
        await ApiService.instance.post('/tv/pair', {'mac': _mac ?? ''}, 75);
    if (!mounted) return;
    setState(() => _busy = false);
    TerminalMessenger.show(
        context, result.success ? 'TV_PAIRED' : 'ERR: ${result.message}',
        isSuccess: result.success, isError: !result.success);
    refresh();
  }

  void _setVolume(double value) {
    setState(() => _volumeDrag = value);
    _volumeDebounce?.cancel();
    _volumeDebounce = Timer(const Duration(milliseconds: 350), () async {
      await _send('volume_set', value.round().toString());
      if (mounted) setState(() => _volumeDrag = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return Center(
          child: _error == null
              ? const TerminalLoading()
              : EmptyState('error: $_error'));
    }
    final online = status['online'] == true;
    final paired = status['paired'] == true;
    final compatible = status['kind'] == 'lg';
    final host = '${status['host'] ?? ''}';

    return RefreshIndicator(
      onRefresh: () async {
        await _loadTvs();
        await refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionTitle('LG_TV',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                StatusDot(online ? Colors.greenAccent : AppColors.comment),
                const SizedBox(width: 6),
                Text(online ? 'on' : 'off',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.comment)),
              ])),
          if (_tvs.length > 1) ...[
            FilterBar(
              options: [
                for (final tv in _tvs)
                  '${tv['name'] ?? tv['ip']}${tv['kind'] == 'lg' ? '' : ' (${tv['kind'] == 'androidtv' ? 'android' : '?'})'}'
              ],
              selected: _tvs.indexWhere((tv) => tv['mac'] == _mac),
              onSelected: (index) => _select('${_tvs[index]['mac']}'),
            ),
            const SizedBox(height: 15),
          ],
          if (host.isEmpty)
            TerminalMessenger.inlineBanner('TV_NOT_FOUND',
                'Ponle la etiqueta "tv" a tu TV en la pestaña network.',
                isError: true)
          else ...[
            Panel(
              child: Column(children: [
                InfoRow('HOST', host, icon: Icons.tv),
                if (online && status['app'] != null)
                  InfoRow('APP', '${status['app']}', icon: Icons.apps),
              ]),
            ),
            if (status['error'] != null) ...[
              const SizedBox(height: 10),
              TerminalMessenger.inlineBanner('TV_ERROR', '${status['error']}',
                  isError: true),
            ],
            const SizedBox(height: 15),
            if (compatible && (!paired || status['error'] != null))
              OutlinedButton.icon(
                onPressed: _busy || !online ? null : _pair,
                icon: const Icon(Icons.link, size: 16),
                label: Text(online ? 'pair()' : 'pair() — enciende la TV'),
              ),
            const SizedBox(height: 10),
            if (compatible) _powerRow(online),
            if (online && paired && compatible) ...[
              const SizedBox(height: 20),
              _volume(status),
              const SizedBox(height: 20),
              _dpad(),
              const SizedBox(height: 15),
              _mediaRow(),
              if (_apps.isNotEmpty) ...[
                const SizedBox(height: 25),
                const SectionTitle('APPS'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final app in _apps)
                      ActionChip(
                        label: Text('${app['title']}',
                            style: const TextStyle(fontSize: 11)),
                        onPressed: () => _send('launch', '${app['id']}'),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _powerRow(bool online) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        TextButton.icon(
          onPressed: () => _send('power_on'),
          icon: const Icon(Icons.power_settings_new,
              size: 16, color: Colors.greenAccent),
          label: const Text('powerOn',
              style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
        ),
        TextButton.icon(
          onPressed: online ? () => _send('power_off') : null,
          icon: const Icon(Icons.power_off, size: 16, color: Colors.redAccent),
          label: const Text('powerOff',
              style: TextStyle(fontSize: 11, color: Colors.redAccent)),
        ),
      ],
    );
  }

  Widget _volume(Map<String, dynamic> status) {
    final current = (status['volume'] as num?)?.toDouble() ?? 0;
    final value = (_volumeDrag ?? current).clamp(0, 100).toDouble();
    final muted = status['muted'] == true;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(children: [
        IconButton(
          icon: Icon(muted ? Icons.volume_off : Icons.volume_up, size: 18),
          onPressed: () => _send('mute', (!muted).toString()),
        ),
        Expanded(
          child: Slider(value: value, min: 0, max: 100, onChanged: _setVolume),
        ),
        SizedBox(
          width: 32,
          child: Text('${value.round()}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _key(IconData icon, String button, {double size = 56}) {
    return SizedBox(
      width: size,
      height: size,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _send('button', button),
        child: Icon(icon, size: 22),
      ),
    );
  }

  Widget _dpad() {
    return Column(children: [
      _key(Icons.keyboard_arrow_up, 'UP'),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _key(Icons.keyboard_arrow_left, 'LEFT'),
        const SizedBox(width: 6),
        _key(Icons.circle_outlined, 'ENTER'),
        const SizedBox(width: 6),
        _key(Icons.keyboard_arrow_right, 'RIGHT'),
      ]),
      const SizedBox(height: 6),
      _key(Icons.keyboard_arrow_down, 'DOWN'),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _key(Icons.arrow_back, 'BACK', size: 48),
        const SizedBox(width: 12),
        _key(Icons.home_outlined, 'HOME', size: 48),
        const SizedBox(width: 12),
        _key(Icons.settings_outlined, 'MENU', size: 48),
      ]),
    ]);
  }

  Widget _mediaRow() {
    Widget media(IconData icon, String action) =>
        IconButton(icon: Icon(icon, size: 22), onPressed: () => _send(action));
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      media(Icons.fast_rewind, 'rewind'),
      media(Icons.play_arrow, 'play'),
      media(Icons.pause, 'pause'),
      media(Icons.fast_forward, 'forward'),
      media(Icons.keyboard_arrow_up, 'channel_up'),
      media(Icons.keyboard_arrow_down, 'channel_down'),
    ]);
  }
}
