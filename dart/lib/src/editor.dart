import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trame/trame.dart';

import 'editing.dart';
import 'layout.dart';
import 'note_syntax.dart';
import 'note_text.dart';
import 'render.dart';
import 'theme.dart';

/// The node of a note's text in its document.
const noteBody = 'body';

/// The editor of a note: its Markdown as it is written, marked as it is
/// typed, with the carets and selections of the others.
///
/// Undo and redo are the session's: they revert this person's edits only.
class BrefEditor extends StatefulWidget {
  const BrefEditor({
    super.key,
    required this.session,
    this.theme,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 120),
    this.width = 760,
    this.focusNode,
    this.autofocus = false,
  });

  final DocSession session;

  /// How the note looks; derived from the app's theme when null.
  final BrefTheme? theme;

  /// Around the text, which keeps at least this much room on each side.
  final EdgeInsets padding;

  /// The widest the column of text grows: wider lines are hard to read.
  final double width;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<BrefEditor> createState() => _BrefEditorState();
}

class _BrefEditorState extends State<BrefEditor> implements DeltaTextInputClient {
  late final NoteText _text = NoteText(_flow);
  late final NoteSyntax _syntax = NoteSyntax(_text);
  NoteLayout? _layout;
  final _marks = NoteMarks();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _menu = ContextMenuController();
  FocusNode? _ownFocus;
  StreamSubscription<Edit>? _changes;

  TextInputConnection? _input;

  /// The part of the text the platform's input sees: the lines around the
  /// caret, so that a long note does not travel at each keystroke.
  var _windowStart = 0, _windowEnd = 0;

  /// The value the platform holds, which it is only sent again when it
  /// differs from what the editor shows.
  TextEditingValue? _platform;

  /// Whether deltas of the platform are being applied: the window they
  /// refer to must not move until all of them are.
  var _receiving = false;

  Timer? _blink;
  double? _goalX;

  /// Whether the change being received is this editor's own edit, and
  /// whether it is an undo or redo, after which the caret goes where it
  /// changed the text.
  var _local = false;
  var _travelling = false;

  var _clicks = 0;
  Duration? _lastClick;
  var _lastClickAt = Offset.zero;

  /// What a double or triple click selected, which dragging extends by
  /// words or lines from.
  (int, int)? _unit;
  Offset? _dragAt;
  Timer? _autoScroll;

  DocSession get _session => widget.session;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  String get _flow => _session.document[noteBody]?.text?.text ?? '\n';

  bool get _editable => _session.loaded && !_session.readOnly;

  RenderNote? get _render => _viewport.currentContext?.findRenderObject() as RenderNote?;

  bool get _apple => const {TargetPlatform.macOS, TargetPlatform.iOS}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _changes = _session.changes.listen(_changed);
    _session.addListener(_sessionChanged);
    _session.presence.addListener(_peersMoved);
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = widget.theme ?? BrefTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final layout = _layout;
    if (layout == null) {
      _layout = NoteLayout(_text, _syntax, theme: theme, scaler: scaler);
    } else {
      layout
        ..theme = theme
        ..scaler = scaler;
    }
  }

  @override
  void didUpdateWidget(BrefEditor old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      unawaited(_changes?.cancel());
      old.session
        ..removeListener(_sessionChanged)
        ..presence.removeListener(_peersMoved);
      _changes = _session.changes.listen(_changed);
      _session
        ..addListener(_sessionChanged)
        ..presence.addListener(_peersMoved);
      _reload();
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (widget.theme != null && old.theme != widget.theme) _layout?.theme = widget.theme!;
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _session
      ..removeListener(_sessionChanged)
      ..presence.removeListener(_peersMoved)
      ..select(null);
    _focus.removeListener(_focusChanged);
    _ownFocus?.dispose();
    _input?.close();
    _menu.remove();
    _blink?.cancel();
    _autoScroll?.cancel();
    _layout?.dispose();
    _marks.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // the document

  void _sessionChanged() {
    if (!mounted) return;
    if (_editable) {
      _openInput();
    } else {
      _closeInput();
    }
    _restartBlink();
    setState(() {});
  }

  void _reload() {
    _text.reset(_flow);
    _syntax.reset();
    _layout?.reload();
    _select(_marks.base, extent: _marks.extent, reveal: false);
  }

  /// Follows a change of the document: its own edits, those of others, and
  /// the whole document when it arrives or comes back.
  void _changed(Edit edit) {
    var base = _marks.base, extent = _marks.extent;
    var windowStart = _windowStart, windowEnd = _windowEnd;
    for (final c in edit.changes) {
      if (c.id != noteBody) continue;
      if (c.kind != ChangeKind.text) {
        _reload();
        return;
      }
      final delta = c.text!;
      final splice = _text.apply(delta);
      if (splice != null) _layout?.splice(splice, _syntax.splice(splice));
      if (_travelling) {
        (base, extent) = _changedRange(delta);
      } else if (!_local) {
        base = delta.transformPosition(base, thisFirst: false);
        extent = delta.transformPosition(extent, thisFirst: false);
      }
      windowStart = delta.transformPosition(windowStart, thisFirst: true);
      windowEnd = delta.transformPosition(windowEnd, thisFirst: false);
    }
    _windowStart = windowStart;
    _windowEnd = windowEnd;
    if (!_local) _select(base, extent: extent, keepGoal: true, reveal: _travelling, publish: _travelling);
    _peersMoved();
  }

  /// Where a delta changed the text: the caret after what it inserted, or
  /// where it deleted.
  (int, int) _changedRange(Delta delta) {
    var at = 0, start = -1, end = 0;
    for (final op in delta.ops) {
      if (op.isRetain) {
        at += op.retain;
        continue;
      }
      if (start < 0) start = at;
      if (op.isInsert) at += op.length;
      end = at;
    }
    return start < 0 ? (_marks.base, _marks.extent) : (end, end);
  }

  void _peersMoved() {
    final length = _text.length;
    _marks
      ..peers = [
        for (final peer in _session.peers)
          if (peer.selection case final s? when s.node == noteBody)
            (sid: peer.sid, name: peer.name, base: math.min(s.base, length), extent: math.min(s.extent, length)),
      ]
      ..changed();
  }

  // editing

  /// Replaces [start] to [end] by [text], and puts the caret after it.
  void _replace(int start, int end, String text) {
    if (!_editable) return;
    _local = true;
    final done = _session.replaceText(noteBody, start, end, text);
    _local = false;
    if (done) _select(start + text.length);
  }

  /// Several replacements made as one edit, the selection following them.
  void _replaceAll(List<Replacement> replacements) {
    if (!_editable || replacements.isEmpty) return;
    final delta = Delta();
    var at = 0;
    for (final r in replacements..sort((a, b) => a.start.compareTo(b.start))) {
      delta
        ..retain(r.start - at)
        ..delete(r.end - r.start)
        ..insert(r.text);
      at = r.end;
    }
    final base = delta.transformPosition(_marks.base, thisFirst: false);
    final extent = delta.transformPosition(_marks.extent, thisFirst: false);
    _local = true;
    final done = _session.edit(Edit([Change.text(noteBody, delta)]));
    _local = false;
    if (done) _select(base, extent: extent);
  }

  void _type(String text) {
    if (text == '\n') {
      final r = _marks.base == _marks.extent ? enter(_text, _marks.extent) : null;
      if (r != null) {
        _replace(r.start, r.end, r.text);
        return;
      }
    }
    _replace(_marks.start, _marks.end, text);
  }

  void _deleteTo(int to) {
    if (_marks.base != _marks.extent) {
      _replace(_marks.start, _marks.end, '');
    } else if (to != _marks.extent) {
      _replace(math.min(to, _marks.extent), math.max(to, _marks.extent), '');
    }
  }

  void _travel({required bool back}) {
    if (!_editable) return;
    _travelling = true;
    back ? _session.undo() : _session.redo();
    _travelling = false;
  }

  Future<void> _copy({bool cut = false}) async {
    if (_marks.base == _marks.extent) return;
    await Clipboard.setData(ClipboardData(text: _text.substring(_marks.start, _marks.end)));
    if (cut) _replace(_marks.start, _marks.end, '');
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) return;
    _replace(_marks.start, _marks.end, text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
  }

  void _indent({required bool outdent}) {
    final s = _marks;
    final list = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s').hasMatch(_text.line(_text.lineAt(s.extent)));
    if (s.base == s.extent && !list && !outdent) {
      _type('\t');
      return;
    }
    _replaceAll(indent(_text, s.start, s.end, outdent: outdent));
  }

  // the selection

  /// Selects [base] to [extent], the caret alone at [base] by default.
  /// The selection is told the others unless it only followed their edits,
  /// which they follow on their side.
  void _select(int base, {int? extent, bool keepGoal = false, bool reveal = true, bool publish = true}) {
    final length = _text.length;
    _marks
      ..base = base.clamp(0, length)
      ..extent = (extent ?? base).clamp(0, length)
      ..changed();
    if (!keepGoal) _goalX = null;
    if (publish) _session.select(DocSelection(noteBody, _marks.base, _marks.extent));
    _restartBlink();
    if (reveal) _reveal(_marks.extent);
    _syncInput();
  }

  void _moveTo(int to, {required bool extend, bool keepGoal = false}) {
    _select(extend ? _marks.base : to, extent: to, keepGoal: keepGoal);
  }

  /// Scrolls the least that shows the caret at [offset].
  void _reveal(int offset) {
    final render = _render;
    if (render == null || !_scroll.hasClients || !render.hasSize) return;
    final caret = render.contentCaretRect(offset);
    final position = _scroll.position;
    final view = render.size.height;
    final margin = math.min(caret.height * 2, view / 4);
    var target = position.pixels;
    if (caret.top - margin < target) {
      target = caret.top - margin;
    } else if (caret.bottom + margin > target + view) {
      target = caret.bottom + margin - view;
    }
    target = target.clamp(position.minScrollExtent, math.max(position.maxScrollExtent, target));
    if (target != position.pixels) position.jumpTo(math.max(0, target));
  }

  /// The offset a row up or down from the caret, or [pages] of the view,
  /// where the caret was first on the row moved from.
  int _vertical(int from, {required bool down, bool page = false}) {
    final layout = _layout!;
    final render = _render;
    final caret = layout.caretRect(from);
    final x = _goalX ??= caret.left;
    final by = page ? (render?.size.height ?? 400) * 0.9 : 1.0;
    final y = down ? caret.bottom + by : caret.top - by;
    if (y < 0) return 0;
    if (y >= layout.height) return _text.length;
    return layout.offsetAt(Offset(x, y));
  }

  void _restartBlink() {
    _blink?.cancel();
    final on = _focus.hasFocus && _editable;
    if (_marks.caret != on) {
      _marks
        ..caret = on
        ..changed();
    }
    if (!on) return;
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      _marks
        ..caret = !_marks.caret
        ..changed();
    });
  }

  // keys

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_marks.composing.isValid && !_marks.composing.isCollapsed) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final command = _apple ? keys.isMetaPressed : keys.isControlPressed;
    final word = _apple ? keys.isAltPressed : keys.isControlPressed;
    final s = _marks;
    final collapsed = s.base == s.extent;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (!shift && !collapsed) {
          _moveTo(s.start, extend: false);
        } else {
          final to = command && _apple
              ? _layout!.rowAt(s.extent).$1
              : (word ? previousWord(_text, s.extent) : previousCharacter(_text, s.extent));
          _moveTo(to, extend: shift);
        }
      case LogicalKeyboardKey.arrowRight:
        if (!shift && !collapsed) {
          _moveTo(s.end, extend: false);
        } else {
          final to = command && _apple
              ? _layout!.rowAt(s.extent).$2
              : (word ? nextWord(_text, s.extent) : nextCharacter(_text, s.extent));
          _moveTo(to, extend: shift);
        }
      case LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.arrowDown:
        final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
        if (command && _apple) {
          _moveTo(down ? _text.length : 0, extend: shift);
        } else {
          _moveTo(_vertical(s.extent, down: down), extend: shift, keepGoal: true);
        }
      case LogicalKeyboardKey.pageUp || LogicalKeyboardKey.pageDown:
        _moveTo(_vertical(s.extent, down: e.logicalKey == LogicalKeyboardKey.pageDown, page: true), extend: shift, keepGoal: true);
      case LogicalKeyboardKey.home:
        _moveTo(command ? 0 : _layout!.rowAt(s.extent).$1, extend: shift);
      case LogicalKeyboardKey.end:
        _moveTo(command ? _text.length : _layout!.rowAt(s.extent).$2, extend: shift);
      case LogicalKeyboardKey.backspace:
        if (!_editable) return KeyEventResult.ignored;
        _deleteTo(command && _apple
            ? _layout!.rowAt(s.extent).$1
            : (word ? previousWord(_text, s.extent) : previousCharacter(_text, s.extent)));
      case LogicalKeyboardKey.delete:
        if (!_editable) return KeyEventResult.ignored;
        _deleteTo(word ? nextWord(_text, s.extent) : nextCharacter(_text, s.extent));
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        if (!_editable) return KeyEventResult.ignored;
        _type('\n');
      case LogicalKeyboardKey.tab:
        if (!_editable) return KeyEventResult.ignored;
        _indent(outdent: shift);
      case LogicalKeyboardKey.keyA when command:
        _select(0, extent: _text.length, reveal: false);
      case LogicalKeyboardKey.keyC when command:
        unawaited(_copy());
      case LogicalKeyboardKey.keyX when command && _editable:
        unawaited(_copy(cut: true));
      case LogicalKeyboardKey.keyV when command && _editable:
        unawaited(_paste());
      case LogicalKeyboardKey.keyZ when command:
        _travel(back: !shift);
      case LogicalKeyboardKey.keyY when command && !_apple:
        _travel(back: false);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // the platform's input

  void _focusChanged() {
    if (_focus.hasFocus) {
      _openInput();
    } else {
      _closeInput();
      _menu.remove();
    }
    _restartBlink();
  }

  void _openInput() {
    if (!_editable || !_focus.hasFocus || (_input?.attached ?? false)) return;
    _platform = null;
    _input = TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        enableDeltaModel: true,
        textCapitalization: TextCapitalization.sentences,
        keyboardAppearance: Theme.of(context).brightness,
      ),
    )..show();
    _syncInput();
  }

  void _closeInput() {
    _input?.close();
    _input = null;
    _platform = null;
    if (_marks.composing.isValid) {
      _marks
        ..composing = TextRange.empty
        ..changed();
    }
  }

  /// Sends the platform the lines around the caret, when they are not what
  /// it holds.
  void _syncInput() {
    final input = _input;
    if (input == null || !input.attached || _receiving) return;
    if (_marks.composing.isValid && !_marks.composing.isCollapsed) return;
    final s = _marks;
    final first = math.max(0, _text.lineAt(s.start) - 1);
    final last = math.min(_text.lineCount - 1, _text.lineAt(s.end) + 1);
    var start = _text.lineStart(first), end = _text.lineEnd(last);
    if (s.start - start > 2000) start = s.start - 2000;
    if (end - s.end > 2000) end = s.end + 2000;
    _windowStart = start;
    _windowEnd = end;
    final value = currentTextEditingValue;
    if (value == _platform) return;
    _platform = value;
    input.setEditingState(value);
    _placeInput();
  }

  /// Tells the platform where the editor and the caret are, for the
  /// windows of input methods.
  void _placeInput() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final input = _input;
      final render = _render;
      if (input == null || !input.attached || render == null || !render.hasSize) return;
      input
        ..setEditableSizeAndTransform(render.size, render.getTransformTo(null))
        ..setCaretRect(render.caretRect(_marks.extent));
    });
  }

  @override
  TextEditingValue get currentTextEditingValue {
    final s = _marks;
    final start = _windowStart, end = math.min(_windowEnd, _text.length);
    int local(int offset) => (offset - start).clamp(0, end - start);
    return TextEditingValue(
      text: _text.substring(start, end),
      selection: TextSelection(baseOffset: local(s.base), extentOffset: local(s.extent)),
      composing: s.composing.isValid ? TextRange(start: local(s.composing.start), end: local(s.composing.end)) : TextRange.empty,
    );
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    _receiving = true;
    for (final delta in deltas) {
      _platform = _platform == null ? null : delta.apply(_platform!);
      final at = _windowStart;
      switch (delta) {
        case TextEditingDeltaInsertion(:final insertionOffset, :final textInserted):
          if (textInserted == '\n' && !delta.composing.isValid) {
            _select(at + insertionOffset);
            _type('\n');
            continue;
          }
          _replace(at + insertionOffset, at + insertionOffset, textInserted);
        case TextEditingDeltaDeletion(:final deletedRange):
          _replace(at + deletedRange.start, at + deletedRange.end, '');
        case TextEditingDeltaReplacement(:final replacedRange, :final replacementText):
          _replace(at + replacedRange.start, at + replacedRange.end, replacementText);
        case TextEditingDeltaNonTextUpdate():
      }
      final composing = delta.composing;
      _marks.composing = composing.isValid && !composing.isCollapsed
          ? TextRange(start: _windowStart + composing.start, end: _windowStart + composing.end)
          : TextRange.empty;
      final selection = delta.selection;
      if (selection.isValid) {
        _select(_windowStart + selection.baseOffset, extent: _windowStart + selection.extentOffset);
      } else {
        _marks.changed();
      }
    }
    _receiving = false;
    _syncInput();
  }

  @override
  void updateEditingValue(TextEditingValue value) {}

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _input = null;
    _platform = null;
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  bool onFocusReceived() {
    _focus.requestFocus();
    return true;
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  // pointers

  void _pointerDown(PointerDownEvent e) {
    _menu.remove();
    _focus.requestFocus();
    final render = _render;
    if (render == null) return;
    final at = render.offsetAt(e.localPosition);
    if (e.kind != PointerDeviceKind.mouse) return;
    if (e.buttons == kSecondaryMouseButton) {
      if (at < _marks.start || at > _marks.end) _select(at);
      _showMenu(e.position);
      return;
    }
    if (e.buttons != kPrimaryMouseButton) return;
    final last = _lastClick;
    final again = last != null && e.timeStamp - last < kDoubleTapTimeout && (e.position - _lastClickAt).distance < kDoubleTapSlop;
    _clicks = again ? _clicks % 3 + 1 : 1;
    _lastClick = e.timeStamp;
    _lastClickAt = e.position;
    _dragAt = e.localPosition;
    if (HardwareKeyboard.instance.isShiftPressed && _clicks == 1) {
      _unit = null;
      _moveTo(at, extend: true);
      return;
    }
    _selectUnit(at);
  }

  /// Selects the caret, word or line at [at] as the clicks so far ask.
  void _selectUnit(int at) {
    final unit = switch (_clicks) {
      2 => wordAt(_text, at),
      3 => (_text.lineStart(_text.lineAt(at)), math.min(_text.lineEnd(_text.lineAt(at)) + 1, _text.length)),
      _ => null,
    };
    _unit = unit;
    if (unit == null) {
      _select(at);
    } else {
      _select(unit.$1, extent: unit.$2);
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton || _dragAt == null) return;
    _dragAt = e.localPosition;
    _dragTo(e.localPosition);
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _scrollWhileDragging());
  }

  void _pointerUp(PointerEvent e) {
    _dragAt = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  void _dragTo(Offset local) {
    final render = _render;
    if (render == null) return;
    final at = render.offsetAt(local);
    final unit = _unit;
    if (unit == null) {
      _moveTo(at, extend: true);
    } else if (at < unit.$1) {
      _select(unit.$2, extent: _clicks == 2 ? wordAt(_text, at).$1 : _text.lineStart(_text.lineAt(at)));
    } else {
      _select(unit.$1, extent: _clicks == 2 ? wordAt(_text, at).$2 : math.min(_text.lineEnd(_text.lineAt(at)) + 1, _text.length));
    }
  }

  /// Scrolls when a drag selecting text goes past the top or the bottom.
  void _scrollWhileDragging() {
    final at = _dragAt;
    final render = _render;
    if (at == null || render == null || !_scroll.hasClients) return;
    final height = render.size.height;
    final by = at.dy < 0 ? at.dy : (at.dy > height ? at.dy - height : 0.0);
    if (by == 0) return;
    final position = _scroll.position;
    position.jumpTo((position.pixels + by / 2).clamp(position.minScrollExtent, position.maxScrollExtent));
    _dragTo(at);
  }

  void _tapUp(TapUpDetails d) {
    if (d.kind == PointerDeviceKind.mouse) return;
    final render = _render;
    if (render == null) return;
    _select(render.offsetAt(d.localPosition));
    _openInput();
    _input?.show();
  }

  void _longPress(LongPressStartDetails d) {
    final render = _render;
    if (render == null) return;
    final (start, end) = wordAt(_text, render.offsetAt(d.localPosition));
    _clicks = 2;
    _select(start, extent: end);
    _unit = (start, end);
    unawaited(HapticFeedback.selectionClick());
  }

  void _longPressMove(LongPressMoveUpdateDetails d) => _dragTo(d.localPosition);

  void _longPressEnd(LongPressEndDetails d) {
    _unit = null;
    _showMenu(d.globalPosition);
  }

  void _showMenu(Offset global) {
    final s = _marks;
    final selected = s.base != s.extent;
    _menu.show(
      context: context,
      contextMenuBuilder: (context) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: global),
        buttonItems: [
          if (selected && _editable)
            ContextMenuButtonItem(type: ContextMenuButtonType.cut, onPressed: () => _menuDone(_copy(cut: true))),
          if (selected) ContextMenuButtonItem(type: ContextMenuButtonType.copy, onPressed: () => _menuDone(_copy())),
          if (_editable) ContextMenuButtonItem(type: ContextMenuButtonType.paste, onPressed: () => _menuDone(_paste())),
          ContextMenuButtonItem(
            type: ContextMenuButtonType.selectAll,
            onPressed: () => _menuDone(Future(() => _select(0, extent: _text.length, reveal: false))),
          ),
        ],
      ),
    );
  }

  void _menuDone(Future<void> action) {
    _menu.remove();
    unawaited(action);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _layout!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(0.0, (constraints.maxWidth - widget.width) / 2);
        final padding = widget.padding.copyWith(
          left: math.max(widget.padding.left, side),
          right: math.max(widget.padding.right, side),
        );
        return Focus(
          focusNode: _focus,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: Scrollbar(
              controller: _scroll,
              child: Scrollable(
                controller: _scroll,
                axisDirection: AxisDirection.down,
                viewportBuilder: (context, offset) => Listener(
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: _pointerUp,
                  onPointerCancel: _pointerUp,
                  child: GestureDetector(
                    onTapUp: _tapUp,
                    onLongPressStart: _longPress,
                    onLongPressMoveUpdate: _longPressMove,
                    onLongPressEnd: _longPressEnd,
                    child: NoteViewport(key: _viewport, offset: offset, layout: layout, marks: _marks, padding: padding),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
