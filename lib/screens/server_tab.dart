import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../services/api_service.dart';
import '../services/terminal_messenger.dart';
import '../widgets/terminal_widgets.dart';
import 'home_screen.dart';

class ServerTab extends StatefulWidget {
  const ServerTab({super.key});

  @override
  State<ServerTab> createState() => _ServerTabState();
}

class _ServerTabState extends State<ServerTab> with Polling {
  Map<String, dynamic>? _status;
  String? _error;

  @override
  Duration get pollInterval => const Duration(seconds: 5);

  @override
  Future<void> refresh() async {
    final result = await ApiService.instance.get('/server/status');
    if (!mounted) return;
    setState(() {
      if (result.success) {
        _status = Map<String, dynamic>.from(result.data);
        _error = null;
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _power(String action, String label) async {
    HapticFeedback.mediumImpact();
    final ok = await confirmAction(context,
        title: '${label.toUpperCase()}_SERVER?',
        message: action == 'reboot'
            ? 'El servidor se reiniciará y sus servicios dejarán de responder unos minutos.'
            : 'El servidor se apagará. Tendrás que encenderlo físicamente.',
        confirmLabel: label.toUpperCase(),
        danger: true);
    if (!ok) return;
    final result = await ApiService.instance.post('/server/$action');
    if (!mounted) return;
    TerminalMessenger.show(
        context,
        result.success
            ? 'SERVER_${label.toUpperCase()}_CMD_SENT'
            : 'ERR: ${result.message}',
        isSuccess: result.success,
        isError: !result.success);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return _error == null
          ? const Center(child: TerminalLoading())
          : _offline();
    }
    final cpu = status['cpu'] as Map;
    final memory = status['memory'] as Map;
    final network = status['network'] as Map;
    final disks = status['disks'] as List;
    final temperature = cpu['temperature'] as num?;
    final load = cpu['load_avg'] as List?;

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ...[
            TerminalMessenger.inlineBanner(
                'SERVER_UNREACHABLE', 'Mostrando los últimos datos recibidos',
                isError: true),
            const SizedBox(height: 15),
          ],
          const SectionTitle('SERVER_INFO'),
          Panel(
            child: Column(
              children: [
                InfoRow('HOSTNAME', '${status['hostname']}', icon: Icons.dns),
                InfoRow('SYSTEM_OS', '${status['os']}', icon: Icons.terminal),
                InfoRow(
                    ApiService.instance.usingRemote
                        ? 'ADDRESS (remote)'
                        : 'ADDRESS',
                    ApiService.instance.address,
                    icon: ApiService.instance.usingRemote
                        ? Icons.public
                        : Icons.lan),
                InfoRow('UPTIME', formatDuration(status['uptime_seconds']),
                    icon: Icons.timer_outlined),
                if (load != null)
                  InfoRow('LOAD_AVG', load.join('  '), icon: Icons.speed),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const SectionTitle('SYSTEM_RESOURCES'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: [
              StatCard(
                  label: 'CPU x${cpu['cores']}',
                  value: '${cpu['percent']}%',
                  progress: (cpu['percent'] as num) / 100,
                  color: AppColors.function),
              StatCard(
                  label: 'RAM ${formatBytes(memory['total'])}',
                  value: '${memory['percent']}%',
                  progress: (memory['percent'] as num) / 100,
                  color: AppColors.keyword),
              StatCard(
                  label: 'TEMP',
                  value: temperature == null ? '--' : '$temperature°C',
                  progress: (temperature ?? 0) / 100,
                  color: Colors.orangeAccent),
              StatCard(
                  label: 'SWAP',
                  value: '${memory['swap_percent']}%',
                  progress: (memory['swap_percent'] as num) / 100,
                  color: AppColors.string),
            ],
          ),
          const SizedBox(height: 25),
          const SectionTitle('STORAGE'),
          Panel(
            child: Column(
              children: [
                for (final disk in disks) _disk(disk as Map),
                if (disks.isEmpty) const EmptyState('sin discos'),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const SectionTitle('NETWORK_IO'),
          Panel(
            child: Column(
              children: [
                InfoRow('DOWNLOAD',
                    '${formatBytes(network['rx_bytes_per_sec'])}/s',
                    icon: Icons.south),
                InfoRow(
                    'UPLOAD', '${formatBytes(network['tx_bytes_per_sec'])}/s',
                    icon: Icons.north),
                InfoRow('TOTAL',
                    '↓ ${formatBytes(network['rx_total'])}   ↑ ${formatBytes(network['tx_total'])}',
                    icon: Icons.swap_vert),
              ],
            ),
          ),
          if (status['allow_power'] == true) ...[
            const SizedBox(height: 25),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () => _power('reboot', 'reboot'),
                  icon: const Icon(Icons.restart_alt,
                      size: 16, color: Colors.orangeAccent),
                  label: const Text('reboot',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orangeAccent)),
                ),
                TextButton.icon(
                  onPressed: () => _power('shutdown', 'shutdown'),
                  icon: const Icon(Icons.power_settings_new,
                      size: 16, color: Colors.redAccent),
                  label: const Text('powerOff',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _disk(Map disk) {
    final percent = (disk['percent'] as num).toDouble();
    final color = percent >= 90
        ? Colors.redAccent
        : percent >= 75
            ? Colors.orangeAccent
            : AppColors.string;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${disk['mount']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Text(
                  '${formatBytes(disk['used'])} / ${formatBytes(disk['total'])}  ',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.comment)),
              Text('${percent.round()}%',
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: percent / 100,
            color: color,
            backgroundColor:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
            minHeight: 2,
          ),
        ],
      ),
    );
  }

  Widget _offline() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TerminalMessenger.inlineBanner('SERVER_UNREACHABLE',
                'Sin respuesta en ${ApiService.instance.address}.',
                isError: true),
            const SizedBox(height: 20),
            TextButton(
                onPressed: refresh, child: const Text('retry_connection()')),
          ],
        ),
      ),
    );
  }
}
