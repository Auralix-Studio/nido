import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

String formatBytes(num? bytes) {
  if (bytes == null) return '--';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatDuration(num? seconds) {
  if (seconds == null) return '--';
  final s = seconds.toInt();
  final days = s ~/ 86400, hours = (s % 86400) ~/ 3600, minutes = (s % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${s}s';
}

/// "hace 5m" a partir de un timestamp unix en segundos.
String formatAgo(num? timestamp) {
  if (timestamp == null) return 'nunca';
  final seconds = DateTime.now().millisecondsSinceEpoch / 1000 - timestamp;
  if (seconds < 60) return 'ahora';
  return 'hace ${formatDuration(seconds)}';
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final bracket = TextStyle(color: primary, fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text('[ ', style: bracket),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
          Text(' ]', style: bracket),
          const Expanded(child: Divider(indent: 10, thickness: 0.5, height: 1)),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  const Panel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(12),
      this.borderColor,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(4);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
            color: borderColor ?? scheme.onSurface.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color color;
  const StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.progress,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 6),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            color: color,
            backgroundColor:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
            minHeight: 2,
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const InfoRow(this.label, this.value, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.comment),
            const SizedBox(width: 10),
          ],
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.comment,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class StatusDot extends StatelessWidget {
  final Color color;
  const StatusDot(this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)],
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  final String text;
  final Color color;
  const TagChip(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

/// Selector tipo terminal: `[todos] online nuevos`.
class FilterBar extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;
  const FilterBar(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      children: [
        for (int i = 0; i < options.length; i++)
          InkWell(
            onTap: () => onSelected(i),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: i == selected
                        ? scheme.primary.withValues(alpha: 0.6)
                        : scheme.onSurface.withValues(alpha: 0.08)),
                color: i == selected
                    ? scheme.primary.withValues(alpha: 0.08)
                    : null,
              ),
              child: Text(options[i],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: i == selected ? scheme.primary : AppColors.comment)),
            ),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text('// $text',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.comment, fontSize: 12)),
    );
  }
}

class TerminalLoading extends StatefulWidget {
  final String text;
  const TerminalLoading({super.key, this.text = '_> nido'});

  @override
  State<TerminalLoading> createState() => _TerminalLoadingState();
}

class _TerminalLoadingState extends State<TerminalLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursor = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400))
    ..repeat(reverse: true);
  Timer? _typing;
  int _chars = 0;

  @override
  void initState() {
    super.initState();
    _typing = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (_chars >= widget.text.length) return timer.cancel();
      setState(() => _chars++);
    });
  }

  @override
  void dispose() {
    _cursor.dispose();
    _typing?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.keyword);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.text.substring(0, _chars), style: style),
            FadeTransition(
                opacity: _cursor,
                child:
                    Container(width: 8, height: 20, color: AppColors.keyword)),
          ],
        ),
        const SizedBox(height: 15),
        const Text('loading...',
            style: TextStyle(fontSize: 11, color: AppColors.comment)),
      ],
    );
  }
}

/// Diálogo de confirmación con estética de terminal.
Future<bool> confirmAction(BuildContext context,
    {required String title,
    required String message,
    String confirmLabel = 'CONFIRM',
    bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(color: danger ? Colors.redAccent : null))),
      ],
    ),
  );
  return result ?? false;
}
