import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cliente del servidor Nido (HTTPS con certificado auto-firmado en LAN o dominio remoto).
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const int defaultPort = 8443;
  static const int discoveryPort = 8444;
  static const String defaultIp = '192.168.1.6';
  static const String defaultRemote = 'nido.aurx.pro';

  final _storage = const FlutterSecureStorage();
  late final HttpClient _http = HttpClient()
    // El certificado auto-firmado solo se acepta en la red local; el dominio
    // externo debe presentar uno válido.
    ..badCertificateCallback = ((cert, host, port) => host != _remote)
    ..connectionTimeout = const Duration(seconds: 4)
    // Menor que el keep-alive del servidor (30 s): nunca se reutiliza una
    // conexión que el servidor ya cerró.
    ..idleTimeout = const Duration(seconds: 10);

  String? _ip = defaultIp;
  int _port = defaultPort;
  String? _token;

  /// Dominio para entrar desde fuera de casa (p. ej. nido.aurx.pro).
  String? _remote = defaultRemote;
  bool _useRemote = false;

  /// Se invoca cuando el servidor rechaza el token (sesión caducada).
  void Function()? onUnauthorized;

  String? get ip => _ip;
  int get port => _port;
  String? get remoteHost => _remote;
  bool get usingRemote => _useRemote;
  bool get hasConfig => _ip != null || _remote != null;

  /// Dirección en uso, para mostrarla en pantalla.
  String get address =>
      _useRemote || _ip == null ? '$_remote' : '$_ip:$_port';
  String get _base =>
      _useRemote || _ip == null ? 'https://$_remote' : 'https://$_ip:$_port';
  bool get _hasAlternative => _ip != null && _remote != null;
  bool get hasToken => _token != null;

  Future<bool> loadSavedConfig() async {
    _ip = await _storage.read(key: 'server_ip') ?? defaultIp;
    _port = int.tryParse(await _storage.read(key: 'server_port') ?? '') ??
        defaultPort;
    _token = await _storage.read(key: 'jwt_token');
    _remote = await _storage.read(key: 'remote_host') ?? defaultRemote;
    return hasConfig;
  }

  Future<void> configure(String? ip, int port, {String? remote}) async {
    _ip = (ip == null || ip.isEmpty) ? null : ip;
    _port = port;
    _remote = (remote == null || remote.isEmpty) ? null : remote;
    _useRemote = false;
    await _storage.write(key: 'server_ip', value: _ip);
    await _storage.write(key: 'server_port', value: port.toString());
    await _storage.write(key: 'remote_host', value: _remote);
  }

  /// Busca el servidor en la red local por broadcast UDP.
  Future<({String ip, int port})?> discoverServer() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final found = Completer<({String ip, int port})?>();
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        final message = utf8.decode(datagram.data, allowMalformed: true);
        final prefix = message.startsWith('NIDO_HERE:')
            ? 'NIDO_HERE:'
            : message.startsWith('AURAHOME_HERE:')
                ? 'AURAHOME_HERE:'
                : null;
        if (prefix == null) return;
        final parts = message.substring(prefix.length).split(':');
        final port = int.tryParse(parts.length > 1 ? parts[1] : '');
        final ip = parts[0].isEmpty ? datagram.address.address : parts[0];
        if (port != null && !found.isCompleted) {
          found.complete((ip: ip, port: port));
        }
      });
      socket.send(utf8.encode('NIDO_DISCOVER'),
          InternetAddress('255.255.255.255'), discoveryPort);
      return await found.future
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<ApiResult> _send(String method, String path,
      {Map<String, dynamic>? body,
      bool auth = true,
      int timeout = 12,
      bool retry = true}) async {
    if (!hasConfig) {
      return const ApiResult(success: false, message: 'server_not_configured');
    }
    try {
      final request = await _http
          .openUrl(method, Uri.parse('$_base$path'))
          .timeout(Duration(seconds: timeout));
      request.headers.contentType = ContentType.json;
      if (auth && _token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response =
          await request.close().timeout(Duration(seconds: timeout));
      final text = await response.transform(utf8.decoder).join();
      final dynamic data = text.isEmpty ? null : jsonDecode(text);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResult(success: true, data: data);
      }
      if (response.statusCode == 401 && auth) {
        await logout();
        onUnauthorized?.call();
      }
      final detail = data is Map ? data['detail'] : null;
      return ApiResult(
        success: false,
        message: detail is String ? detail : 'server_error',
        statusCode: response.statusCode,
      );
    } on TimeoutException {
      return const ApiResult(success: false, message: 'timeout');
    } on SocketException {
      // Sin conexión por esta vía: probar la otra (casa <-> fuera de casa).
      // No se llegó a enviar nada, así que repetir es seguro.
      if (retry && _hasAlternative) {
        _useRemote = !_useRemote;
        return _send(method, path,
            body: body, auth: auth, timeout: timeout, retry: false);
      }
      return const ApiResult(success: false, message: 'server_unreachable');
    } on HttpException catch (e) {
      // Conexión cortada a medias: las lecturas se pueden repetir sin riesgo.
      if (retry && method == 'GET') {
        return _send(method, path, auth: auth, timeout: timeout, retry: false);
      }
      return ApiResult(success: false, message: e.message);
    } catch (e) {
      return ApiResult(success: false, message: e.toString());
    }
  }

  Future<ApiResult> get(String path, {int timeout = 12}) =>
      _send('GET', path, timeout: timeout);
  Future<ApiResult> post(String path,
          [Map<String, dynamic>? body, int timeout = 12]) =>
      _send('POST', path, body: body, timeout: timeout);
  Future<ApiResult> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body: body);
  Future<ApiResult> delete(String path) => _send('DELETE', path);

  Future<ApiResult> login(String pin) async {
    final result =
        await _send('POST', '/auth/login', body: {'pin': pin}, auth: false);
    if (result.success) {
      _token = result.data['token'] as String?;
      await _storage.write(key: 'jwt_token', value: _token);
    }
    return result;
  }

  /// Comprueba el servidor empezando por la red local.
  Future<bool> isServerReachable() async {
    _useRemote = false;
    final result = await _send('GET', '/ping', auth: false, timeout: 6);
    final service = result.data?['service'];
    return result.success && (service == 'nido' || service == 'aura-home');
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: 'jwt_token');
  }

  Future<void> resetApp() async {
    _token = null;
    _ip = defaultIp;
    _remote = defaultRemote;
    _useRemote = false;
    _port = defaultPort;
    await _storage.deleteAll();
  }
}

class ApiResult {
  final bool success;
  final dynamic data;
  final String? message;
  final int? statusCode;
  const ApiResult(
      {required this.success, this.data, this.message, this.statusCode});
}
