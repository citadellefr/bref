import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ot/delta.dart';
import 'session.dart';

/// A plain text editor on a [DocSession], one line per paragraph, where the
/// selections of others show in their colour.
///
/// Undo and redo are the session's: they revert this person's edits only.
class PlainTextEditor extends StatefulWidget {
  const PlainTextEditor({
    super.key,
    required this.session,
    this.style,
    this.padding = const EdgeInsets.all(16),
    this.focusNode,
    this.autofocus = false,
  });

  final DocSession session;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final FocusNode? focusNode;
  final bool autofocus;

  /// The colour a peer is shown in, the same on every screen.
  static Color colorOf(DocPeer peer) => _palette[peer.sid % _palette.length];

  static const _palette = [
    Color(0xFFE8710A),
    Color(0xFF1A73E8),
    Color(0xFF188038),
    Color(0xFFD01884),
    Color(0xFF9334E6),
    Color(0xFF12B5CB),
    Color(0xFFB06000),
    Color(0xFFD93025),
  ];

  @override
  State<PlainTextEditor> createState() => _PlainTextEditorState();
}

class _PlainTextEditorState extends State<PlainTextEditor> {
  late final _PresenceController _controller;
  StreamSubscription<Delta>? _changes;
  var _updating = false;
  var _selection = const TextSelection.collapsed(offset: 0);

  DocSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _controller = _PresenceController(_session)..text = _session.text;
    _controller.addListener(_edited);
    _changes = _session.changes.listen(_changed);
    _session.addListener(_rebuild);
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _session.removeListener(_rebuild);
    _session.unselect();
    _controller.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// Turns what the field did into an edit of the document.
  void _edited() {
    if (_updating) return;
    final value = _controller.value;
    final old = _session.text;
    if (value.text != old) {
      final (start, end, inserted) = _replaced(old, value.text, _selection, value.selection);
      if (!_session.replaceText(start, end, inserted)) {
        _set(TextEditingValue(text: old, selection: _selection));
        return;
      }
    }
    _selection = value.selection;
    if (value.selection.isValid) {
      _session.select(value.selection.baseOffset, value.selection.extentOffset);
    }
  }

  /// Follows a change of the document the field did not make.
  void _changed(Delta change) {
    if (_controller.text == _session.text) return;
    int move(int offset) => offset < 0 ? offset : change.transformPosition(offset, thisFirst: false);
    final value = _controller.value;
    final selection = value.selection.copyWith(
      baseOffset: move(value.selection.baseOffset),
      extentOffset: move(value.selection.extentOffset),
    );
    final composing = value.composing.isValid
        ? TextRange(start: move(value.composing.start), end: move(value.composing.end))
        : TextRange.empty;
    _set(TextEditingValue(text: _session.text, selection: selection, composing: composing));
  }

  void _set(TextEditingValue value) {
    _updating = true;
    _controller.value = value;
    _selection = value.selection;
    _updating = false;
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(onInvoke: (_) => _session.undo()),
        RedoTextIntent: CallbackAction<RedoTextIntent>(onInvoke: (_) => _session.redo()),
      },
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        readOnly: _session.readOnly || !_session.loaded,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: widget.style,
        decoration: InputDecoration(border: InputBorder.none, contentPadding: widget.padding),
      ),
    );
  }
}

/// Where [now] differs from [old]: the range of [old] replaced and the text
/// put there. The selections before and after tell which of several equal
/// characters was typed or deleted, and a surrogate pair is never split.
(int, int, String) _replaced(String old, String now, TextSelection before, TextSelection after) {
  var prefix = 0;
  final shorter = math.min(old.length, now.length);
  while (prefix < shorter && old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
    prefix++;
  }
  if (before.isValid && after.isValid) prefix = math.min(prefix, math.min(before.start, after.start));
  if (prefix > 0 && _isHigh(old.codeUnitAt(prefix - 1))) prefix--;
  var suffix = 0;
  while (suffix < old.length - prefix &&
      suffix < now.length - prefix &&
      old.codeUnitAt(old.length - 1 - suffix) == now.codeUnitAt(now.length - 1 - suffix)) {
    suffix++;
  }
  if (suffix > 0 && suffix < old.length && _isHigh(old.codeUnitAt(old.length - 1 - suffix))) suffix--;
  return (prefix, old.length - suffix, now.substring(prefix, now.length - suffix));
}

bool _isHigh(int unit) => unit >= 0xD800 && unit < 0xDC00;

/// Paints the selections of others behind the text.
class _PresenceController extends TextEditingController {
  _PresenceController(this.session) {
    session.presence.addListener(notifyListeners);
  }

  final DocSession session;

  @override
  void dispose() {
    session.presence.removeListener(notifyListeners);
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final marks = <(int, int, Color)>[];
    for (final peer in session.peers) {
      final s = peer.selection;
      if (s == null) continue;
      var start = math.min(s.$1, s.$2).clamp(0, text.length);
      var end = math.max(s.$1, s.$2).clamp(0, text.length);
      if (start == end) {
        // a caret: the character it stands before, or after at the end
        if (text.isEmpty) continue;
        if (end < text.length) {
          end++;
        } else {
          start--;
        }
      }
      marks.add((start, end, PlainTextEditor.colorOf(peer)));
    }
    if (marks.isEmpty || (withComposing && value.composing.isValid && !value.composing.isCollapsed)) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final cuts = {0, text.length, for (final m in marks) ...[m.$1, m.$2]}.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i + 1 < cuts.length; i++)
          if (cuts[i] < cuts[i + 1])
            TextSpan(
              text: text.substring(cuts[i], cuts[i + 1]),
              style: _markAt(marks, cuts[i], cuts[i + 1]),
            ),
      ],
    );
  }

  static TextStyle? _markAt(List<(int, int, Color)> marks, int start, int end) {
    for (final (from, to, color) in marks.reversed) {
      if (from <= start && end <= to) return TextStyle(backgroundColor: color.withValues(alpha: 0.25));
    }
    return null;
  }
}
