import 'package:flutter/material.dart';
import '../config/theme.dart';

/// A history row that expands on tap to reveal full details + notes.
///
/// Reused across every log screen (feeding, sleep, diaper, health, tummy time)
/// so the "tap a history item to see its notes and full details" behaviour is
/// consistent everywhere. The caller supplies the collapsed [header] content
/// (icons, label, time, amount), the [details] label/value rows to show when
/// expanded, and the free-text [notes].
class ExpandableHistoryTile extends StatefulWidget {
  /// Collapsed-row content (without the trailing chevron — this adds it).
  final Widget header;

  /// Label/value rows shown when expanded, e.g. ('Amount', '150 ml').
  final List<(String, String)> details;

  /// Free-text note for this entry (shown when expanded; "No notes added." if empty).
  final String? notes;

  const ExpandableHistoryTile({
    super.key,
    required this.header,
    this.details = const [],
    this.notes,
  });

  @override
  State<ExpandableHistoryTile> createState() => _ExpandableHistoryTileState();
}

class _ExpandableHistoryTileState extends State<ExpandableHistoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(child: widget.header),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: context.palette.muted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: context.palette.muted.withValues(alpha: 0.15)),
            const SizedBox(height: 10),
            for (final d in widget.details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.$1,
                        style: TextStyle(fontSize: 12, color: context.palette.muted)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        d.$2,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Notes',
                  style: TextStyle(fontSize: 11, color: context.palette.muted)),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                hasNotes ? notes : 'No notes added.',
                style: TextStyle(
                  fontSize: 13,
                  color: hasNotes ? context.palette.text : context.palette.muted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
