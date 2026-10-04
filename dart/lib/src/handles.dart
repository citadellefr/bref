import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'render.dart';

/// The handles a finger moves the ends of a selection with, drawn as the
/// platform draws them.
class SelectionHandles extends StatefulWidget {
  const SelectionHandles({super.key, required this.marks, required this.scroll, required this.note, required this.onMoved});

  final NoteMarks marks;
  final ScrollController scroll;
  final RenderNote? Function() note;

  /// Called with the new ends of the selection as a handle moves.
  final void Function(int base, int extent) onMoved;

  @override
  State<SelectionHandles> createState() => _SelectionHandlesState();
}

class _SelectionHandlesState extends State<SelectionHandles> {
  /// Where the finger holds the handle being dragged, on the line it points
  /// at, and the end of the selection that stays.
  Offset? _at;
  var _fixed = 0;

  TextSelectionControls get _controls =>
      const {TargetPlatform.iOS, TargetPlatform.macOS}.contains(defaultTargetPlatform)
      ? cupertinoTextSelectionHandleControls
      : materialTextSelectionHandleControls;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.marks, widget.scroll]),
      builder: (context, _) {
        final note = widget.note();
        final marks = widget.marks;
        if (note == null || !note.hasSize || marks.start == marks.end) return const SizedBox.shrink();
        return Stack(
          children: [
            _handle(context, note, TextSelectionHandleType.left, marks.start, start: true),
            _handle(context, note, TextSelectionHandleType.right, marks.end, start: false),
          ],
        );
      },
    );
  }

  Widget _handle(BuildContext context, RenderNote note, TextSelectionHandleType type, int offset, {required bool start}) {
    final caret = note.caretRect(offset);
    if (caret.bottom < 0 || caret.top > note.size.height) return const SizedBox.shrink();
    final height = caret.height;
    final anchor = _controls.getHandleAnchor(type, height);
    final size = _controls.getHandleSize(height);
    final point = Offset(caret.left, caret.bottom);
    return Positioned(
      left: point.dx - anchor.dx,
      top: point.dy - anchor.dy,
      width: size.width,
      height: size.height,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          _at = point - Offset(0, height / 2);
          _fixed = start ? widget.marks.end : widget.marks.start;
        },
        onPointerMove: (e) {
          final at = _at;
          if (at == null) return;
          widget.onMoved(_fixed, note.offsetAt(_at = at + e.delta));
        },
        onPointerUp: (_) => _at = null,
        onPointerCancel: (_) => _at = null,
        child: _controls.buildHandle(context, type, height),
      ),
    );
  }
}
