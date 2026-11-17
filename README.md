# Nido — app

Cliente Flutter para administrar tu servidor y tu red local desde casa.
Necesita el servicio [`nido-server`](https://github.com/Auralix-Studio/nido-server) corriendo en el servidor.

## Pestañas

- **server**: recursos en tiempo real (CPU, RAM, temperatura, discos, red), reinicio y apagado.
- **services**: servicios systemd y contenedores Docker. Toca uno para iniciar/detener/reiniciar, ver logs o fijarlo (`pin()`); si un servicio fijado se cae, genera una alerta.
- **network**: quién está conectado ahora, quién se ha visto y qué dispositivos son nuevos. Toca uno para ponerle nombre, tipo y marcarlo como conocido.
- **alerts**: historial de eventos (dispositivo nuevo, servicio caído, intentos de acceso).

## Primer uso

1. Conecta el móvil al WiFi de casa.
2. Abre la app: busca el servidor sola. Si no lo encuentra, entra en `configure_network()` y escribe la IP y el puerto (8443).
3. Introduce el PIN que definiste al instalar el servidor.
4. En **network**, pulsa `trust_all()` para marcar como conocidos los dispositivos actuales. A partir de ahí, cualquiera que aparezca saldrá como `NEW`.

## Compilación

```bash
flutter pub get
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`.
