// Small pieces for laying out the app's words (content pass, 2026-11-16: "properly structured and formatted and not
// looking like a bunch of AI generated texts strung together"): a short list of points instead of a long sentence,
// and details on demand instead of a wall of text.
import 'package:flutter/material.dart';

import 'premium.dart';

/// A short list: one idea per line, each after a small dot, in the surrounding text style.
class Points extends StatelessWidget {
  const Points(this.lines, {super.key, this.style, this.gap = Space.xs});
  final List<String> lines;
  final TextStyle? style;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? DefaultTextStyle.of(context).style;
    final size = style.fontSize ?? 14;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final (i, line) in lines.indexed)
        Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : gap), child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the dot sits on the first line's middle, whatever the text size
          SizedBox(width: size * 1.1, height: size * (style.height ?? 1.4) * MediaQuery.textScalerOf(context).scale(1),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Container(width: 5, height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: style.color?.withValues(alpha: 0.7) ??
                      Theme.of(context).colorScheme.onSurfaceVariant)))),
          Expanded(child: Text(line, style: style)),
        ])),
    ]);
  }
}

/// A "Details" link that shows [child] under it on demand, and hides it again.
class MoreDetails extends StatefulWidget {
  const MoreDetails({super.key, required this.child, this.label = 'Details', this.buttonKey});
  final Widget child;
  final String label;
  final Key? buttonKey;

  @override
  State<MoreDetails> createState() => _MoreDetailsState();
}

class _MoreDetailsState extends State<MoreDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min, children: [
    Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: widget.buttonKey,
        onPressed: () => setState(() => _open = !_open),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.s)),
        icon: AnimatedRotation(turns: _open ? 0.5 : 0, duration: Calm.of(context, Calm.quick), curve: Calm.curve,
            child: const Icon(Icons.expand_more_rounded, size: 20)),
        label: Text(_open ? 'Hide details' : widget.label))),
    AnimatedSize(duration: Calm.of(context, Calm.normal), curve: Calm.curve, alignment: Alignment.topCenter,
        child: _open ? Padding(padding: const EdgeInsets.only(top: Space.xs), child: widget.child)
            : const SizedBox(width: double.infinity)),
  ]);
}
