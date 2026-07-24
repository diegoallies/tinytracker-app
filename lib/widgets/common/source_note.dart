import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../utils/care_pack_data.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';

/// A small tappable citation line placed next to medical content
/// (Apple guideline 1.4.1). Opens the cited page externally.
class SourceNote extends StatelessWidget {
  final CareSource source;

  /// Text shown before the source name, e.g. 'Fever bands:'.
  final String? prefix;

  const SourceNote({super.key, required this.source, this.prefix});

  Future<void> _open(BuildContext context) async {
    Haptics.lightTap();
    try {
      final ok = await launchUrl(
        Uri.parse(source.url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        context.showErrorSnackBar('Couldn’t open the source link.');
      }
    } catch (_) {
      if (context.mounted) {
        context.showErrorSnackBar('Couldn’t open the source link.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.menu_book_rounded,
                size: 14, color: context.palette.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${prefix != null ? '$prefix ' : 'Source: '}'
                '${source.publisher} - ${source.title}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.muted,
                  decoration: TextDecoration.underline,
                  decorationColor:
                      context.palette.muted.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded,
                size: 12, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}
