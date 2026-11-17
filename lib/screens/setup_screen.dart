import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/terminal_messenger.dart';
import '../widgets/terminal_widgets.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _remoteController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final api = ApiService.instance;
    _ipController.text = api.ip ?? '';
    _portController.text = api.port.toString();
    _remoteController.text = api.remoteHost ?? '';
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _remoteController.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() => _busy = true);
    final found = await ApiService.instance.discoverServer();
    if (!mounted) return;
    setState(() => _busy = false);
    if (found == null) {
      TerminalMessenger.show(context, 'SERVER_NOT_FOUND_ON_LAN', isError: true);
      return;
    }
    _ipController.text = found.ip;
    _portController.text = found.port.toString();
    TerminalMessenger.show(context, 'SERVER_FOUND: ${found.ip}',
        isSuccess: true);
  }

  Future<void> _save() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ??
        ApiService.defaultPort;
    final remote = _remoteController.text
        .trim()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    if (ip.isEmpty && remote.isEmpty) return;
    setState(() => _busy = true);
    await ApiService.instance.configure(ip, port, remote: remote);
    final reachable = await ApiService.instance.isServerReachable();
    if (!mounted) return;
    setState(() => _busy = false);
    TerminalMessenger.show(
      context,
      reachable ? 'CONNECTION_SUCCESS' : 'CONNECTION_FAILED',
      isSuccess: reachable,
      isError: !reachable,
    );
    if (reachable) Navigator.pop(context);
  }

  Future<void> _reset() async {
    final ok = await confirmAction(context,
        title: 'RESET_ALL_CONFIG?',
        message: 'Se borrará la IP, el puerto y la sesión guardados en esta app.',
        confirmLabel: 'RESET',
        danger: true);
    if (!ok) return;
    await ApiService.instance.resetApp();
    if (!mounted) return;
    _ipController.clear();
    _remoteController.clear();
    _portController.text = ApiService.defaultPort.toString();
    TerminalMessenger.show(context, 'APP_CONFIG_CLEARED', isSuccess: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ENV_CONFIG'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(30),
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _discover,
            icon: const Icon(Icons.wifi_find, size: 16),
            label: const Text('discover_server()'),
          ),
          const SizedBox(height: 25),
          _field('SERVER_IP', _ipController, '192.168.1.6'),
          const SizedBox(height: 15),
          _field('PORT', _portController, '8443'),
          const SizedBox(height: 15),
          _field('REMOTE_HOST (fuera de casa)', _remoteController,
              'nido.aurx.pro'),
          const SizedBox(height: 40),
          OutlinedButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('apply_changes()'),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _busy ? null : _reset,
            icon: const Icon(Icons.delete_forever,
                size: 16, color: Colors.redAccent),
            label: const Text('factory_reset()',
                style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
              hintText: hint, border: const OutlineInputBorder()),
        ),
      ],
    );
  }
}
