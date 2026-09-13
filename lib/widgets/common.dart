import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/models.dart';

Future<void> openLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !(safeWebUrl(value) || ['mailto', 'tel'].contains(uri.scheme))) {
    return;
  }
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Unavailable');
    }
  } catch (_) {
    if (context.mounted) notice(context, 'This link could not be opened.');
  }
}

void notice(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
void showPage(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

class ContentPage extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const ContentPage({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(child: child),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SectionTitle(this.title, {super.key, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(subtitle!),
          ),
      ],
    ),
  );
}

class ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class ContentImage extends StatelessWidget {
  final String? source;
  final double? height;
  final BoxFit fit;
  const ContentImage(
    this.source, {
    super.key,
    this.height,
    this.fit = BoxFit.cover,
  });
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext c, Object e, StackTrace? s) => SizedBox(
      height: height ?? 140,
      child: const Center(child: Icon(Icons.image_outlined)),
    );
    if (source == null) return fallback(context, '', null);
    return source!.startsWith('assets/')
        ? Image.asset(
            source!,
            height: height,
            width: double.infinity,
            fit: fit,
            errorBuilder: fallback,
          )
        : Image.network(
            source!,
            height: height,
            width: double.infinity,
            fit: fit,
            errorBuilder: fallback,
          );
  }
}

class AsyncButton extends StatefulWidget {
  final String label;
  final Future<void> Function() onPressed;
  const AsyncButton({super.key, required this.label, required this.onPressed});
  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<AsyncButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.onPressed();
            } catch (_) {
              if (context.mounted) {
                notice(
                  context,
                  'Could not complete that action. Please try again.',
                );
              }
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
    child: Text(busy ? 'Please wait…' : widget.label),
  );
}
