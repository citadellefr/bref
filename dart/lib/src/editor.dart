import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trame/trame.dart';

import 'clipboard.dart';
import 'controller.dart';
import 'editing.dart';
import 'handles.dart';
import 'host.dart';
import 'host_cache.dart';
import 'layout.dart';
import 'mentions.dart';
import 'note_syntax.dart';
import 'note_text.dart';
import 'render.dart';
import 'strings.dart';
import 'theme.dart';

export 'note_text.dart' show noteBody;

/// The editor of a note: its Markdown as it reads, the syntax of the lines
/// being edited shown as it is written, with the carets and selections of
/// the others.
///
/// Undo and redo are the session's: they revert this person's edits only.
class BrefEditor extends StatefulWidget {
  const BrefEditor({
    super.key,
    required this.session,
    this.host,
    this.theme,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 120),
    this.width = 760,
    this.focusNode,
    this.autofocus = false,
    this.preview = true,
    this.comments,
    this.follow,
    this.strings = const BrefStrings(),
  });

  final DocSession session;

  /// The comments of the note: their passages are marked, and a click on
  /// one opens its thread. Without it the note has none; give it only when
  /// the server keeps them.
  final BrefComments? comments;

  /// Whose caret the view follows, if anyone's.
  final BrefFollow? follow;
  final BrefStrings strings;

  /// What links stand for and how they open; without it, they do not.
  final BrefHost? host;

  /// How the note looks; derived from the app's theme when null.
  final BrefTheme? theme;

  /// Around the text, which keeps at least this much room on each side.
  final EdgeInsets padding;

  /// The widest the column of text grows: wider lines are hard to read.
  final double width;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Whether the note reads as it renders, the syntax hidden but on the
  /// lines being edited; else all of it is shown as written.
  final bool preview;

  @override
  State<BrefEditor> createState() => BrefEditorState();
}

/// The state of a [BrefEditor], which pictures are given to, from the
/// clipboard of the app or dropped on it.
class BrefEditorState extends State<BrefEditor> implements DeltaTextInputClient {
  late final NoteText _text = NoteText(_flow);
  late final NoteSyntax _syntax = NoteSyntax(_text);
  NoteLayout? _layout;
  final _marks = NoteMarks();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _menu = ContextMenuController();
  FocusNode? _ownFocus;
  StreamSubscription<Edit>? _changes;
  void Function()? _unwatchPaste;

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

  /// Whether the selection was last made by touch: its handles show then.
  final _touch = ValueNotifier(false);

  var _cursor = SystemMouseCursors.text;

  /// The link pointed at, the wait before its card shows, and the card.
  Uri? _pointed;
  Timer? _resting;
  OverlayEntry? _card;

  /// The mention being typed: its trigger and where it starts, the text
  /// typed after it, the keyword that text starts with and what is
  /// written after it, and what the host proposes.
  ({String trigger, int start})? _mention;
  String? _query;
  Command? _command;
  var _typed = '';
  List<Proposal> _found = const [];
  var _chosen = 0;
  var _searches = 0;
  var _searching = false;
  var _searchFailed = false;

  /// Where the keyword is that Escape closed the menu of: typing after it
  /// does not open it again.
  int? _dismissed;

  /// The question a keyword is answering, which nobody edits the note
  /// from here meanwhile.
  _Asking? _asking;
  final _mentionMenu = OverlayPortalController();

  HostCache? _cache;

  /// Where the pictures being uploaded go, following the edits.
  final _uploads = <_Upload>[];

  DocSession get _session => widget.session;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  String get _flow => _session.document[noteBody]?.text?.text ?? '\n';

  bool get _editable => _session.loaded && !_session.readOnly && _asking == null;

  /// Whether an answer is on its way into the note, which is not ready to
  /// leave its editor meanwhile.
  bool get answering => _asking != null;

  RenderNote? get _render => _viewport.currentContext?.findRenderObject() as RenderNote?;

  bool get _apple => const {TargetPlatform.macOS, TargetPlatform.iOS}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _changes = _session.changes.listen(_changed);
    _unwatchPaste = watchPaste(_pasted);
    _session.addListener(_sessionChanged);
    _session.presence.addListener(_peersMoved);
    _focus.addListener(_focusChanged);
    widget.comments?.addListener(_passagesChanged);
    widget.follow?.addListener(_followChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = widget.theme ?? BrefTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final layout = _layout;
    if (layout == null) {
      _makeCache();
      _layout = NoteLayout(_text, _syntax, theme: theme, scaler: scaler, preview: widget.preview)..cache = _cache;
      _passagesChanged();
    } else {
      layout
        ..theme = theme
        ..scaler = scaler;
    }
    _cache?.configuration = createLocalImageConfiguration(context);
  }

  void _makeCache() {
    _cache?.dispose();
    final host = widget.host;
    _cache = host == null ? null : HostCache(host, onChanged: (dest) => _layout?.answered(dest), onFrame: _marks.changed);
    _cache?.configuration = createLocalImageConfiguration(context);
  }

  @override
  void didUpdateWidget(BrefEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      unawaited(_changes?.cancel());
      oldWidget.session
        ..removeListener(_sessionChanged)
        ..presence.removeListener(_peersMoved);
      _changes = _session.changes.listen(_changed);
      _session
        ..addListener(_sessionChanged)
        ..presence.addListener(_peersMoved);
      _reload();
    }
    if (oldWidget.comments != widget.comments) {
      oldWidget.comments?.removeListener(_passagesChanged);
      widget.comments?.addListener(_passagesChanged);
      _passagesChanged();
    }
    if (oldWidget.follow != widget.follow) {
      oldWidget.follow?.removeListener(_followChanged);
      widget.follow?.addListener(_followChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
    if (oldWidget.host != widget.host) {
      _stopAsking();
      _endMention();
      _makeCache();
      _layout?.cache = _cache;
    }
    if (widget.theme != null && oldWidget.theme != widget.theme) _layout?.theme = widget.theme!;
    _layout?.preview = widget.preview;
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _unwatchPaste?.call();
    _asking?.stop();
    _session
      ..removeListener(_sessionChanged)
      ..presence.removeListener(_peersMoved)
      ..select(null);
    _focus.removeListener(_focusChanged);
    widget.comments?.removeListener(_passagesChanged);
    widget.follow?.removeListener(_followChanged);
    _ownFocus?.dispose();
    _input?.close();
    _menu.remove();
    _unpoint();
    _blink?.cancel();
    _autoScroll?.cancel();
    _layout?.dispose();
    _cache?.dispose();
    _marks.dispose();
    _touch.dispose();
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
    _revealSelection();
    _restartBlink();
    setState(() {});
  }

  void _reload() {
    _stopAsking();
    _endMention();
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
    var mention = _mention;
    final asking = _asking;
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
      if (mention != null) mention = (trigger: mention.trigger, start: delta.transformPosition(mention.start, thisFirst: true));
      if (asking != null) asking.end = delta.transformPosition(asking.end, thisFirst: false);
      for (final u in _uploads) {
        u.at = delta.transformPosition(u.at, thisFirst: true);
      }
    }
    _windowStart = windowStart;
    _windowEnd = windowEnd;
    _mention = mention;
    if (!_local) _select(base, extent: extent, keepGoal: true, reveal: _travelling, publish: _travelling);
    _peersMoved();
    if (widget.comments != null) _passagesChanged();
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

  // comments and authorship

  /// Colors the passages of the threads, the one open stronger and those
  /// resolved not at all, and under them what each person wrote when the
  /// note shows it.
  void _passagesChanged() {
    final comments = widget.comments;
    final theme = widget.theme ?? BrefTheme.of(context);
    final length = _text.length;
    final passages = <Passage>[];
    if (comments != null) {
      if (comments.authorship) {
        var at = 0;
        for (final op in _session.document[noteBody]?.text?.ops ?? const <Op>[]) {
          final by = op.attributes?['by'];
          if (by != null) passages.add((from: at, to: at + op.length, color: theme.author(by).withValues(alpha: 0.25)));
          at += op.length;
        }
      }
      for (final t in comments.threads) {
        final open = t.id == comments.selected;
        if (t.done && !open) continue;
        for (final r in t.ranges) {
          passages.add((from: r.start, to: r.end, color: Colors.amber.withValues(alpha: open ? 0.5 : 0.28)));
        }
      }
      if (comments.draft case final d?) passages.add((from: d.start, to: d.end, color: Colors.amber.withValues(alpha: 0.5)));
    }
    _marks
      ..passages = [for (final p in passages) (from: math.min(p.from, length), to: math.min(p.to, length), color: p.color)]
      ..changed();
  }

  void _followChanged() => _followPeer(_text.length);

  /// Scrolls to the caret of the person followed, and stops once they left.
  void _followPeer(int length) {
    final follow = widget.follow;
    final sid = follow?.sid;
    if (sid == null) return;
    final peer = _session.peers.where((p) => p.sid == sid).firstOrNull;
    if (peer == null) {
      follow!.stop();
    } else if (peer.selection case final s? when s.node == noteBody) {
      _reveal(math.min(s.extent, length));
    }
  }

  /// Starts a comment about the selection, or the word at the caret.
  void comment() {
    final comments = widget.comments;
    if (comments == null || !_editable) return;
    var (start, end) = (_marks.start, _marks.end);
    if (start == end) (start, end) = wordAt(_text, start);
    if (start == end) return;
    comments.startDraft(TextRange(start: start, end: end));
  }

  /// Opens the thread of the passage at the caret, if any.
  void _openThreadAt(int offset) {
    final comments = widget.comments;
    if (comments == null || _marks.base != _marks.extent) return;
    for (final t in comments.threads) {
      if (t.covers(offset) && (!t.done || t.id == comments.selected)) {
        comments.select(t.id);
        return;
      }
    }
  }

  void _peersMoved() {
    final length = _text.length;
    _followPeer(length);
    _marks
      ..peers = [
        for (final peer in _session.peers)
          if (peer.selection case final s? when s.node == noteBody)
            (sid: peer.sid, name: peer.name, base: math.min(s.base, length), extent: math.min(s.extent, length)),
      ]
      ..changed();
  }

  // editing

  /// Who this person is, which signs what they write; the server signs it
  /// when it does not know.
  Attributes? get _by => _session.id.isEmpty ? null : {'by': _session.id};

  /// Replaces [start] to [end] by [text], signed, as an edit of this person.
  bool _edit(int start, int end, String text) {
    _local = true;
    final done = _session.edit(Edit([
      Change.text(
        noteBody,
        Delta()
          ..retain(start)
          ..delete(end - start)
          ..insert(text, _by),
      ),
    ]));
    _local = false;
    return done;
  }

  /// Replaces [start] to [end] by [text], and puts the caret after it.
  void _replace(int start, int end, String text) {
    if (!_editable || !_edit(start, end, text)) return;
    _select(start + text.length);
    if (text.isNotEmpty && text.length <= 2 && _mention == null) _startMention();
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
        ..insert(r.text, _by);
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
    if (text == '\n' && _found.isNotEmpty) {
      _found[_chosen].take();
      return;
    }
    if (text == '\n') {
      if (_tableMove(rows: 1)) return;
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
    _pasteText(text);
  }

  void _pasteText(String text) => _replace(_marks.start, _marks.end, text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));

  bool _pasted(String text) {
    if (!_editable || !_focus.hasFocus) return false;
    _pasteText(text);
    return true;
  }

  /// Moves the caret in a table, by cells or rows, adding a row past its end;
  /// whether it was in one.
  bool _tableMove({int rows = 0, int columns = 0}) {
    if (_layout?.preview != true) return false;
    final move = moveInTable(_text, _syntax, _marks.extent, rows: rows, columns: columns);
    if (move == null) return false;
    final insert = move.insert;
    if (insert != null && (!_editable || !_edit(insert.start, insert.end, insert.text))) return true;
    _select(move.base, extent: move.extent);
    return true;
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

  // mentions

  /// Starts a mention when what was just typed ends a trigger, typed at the
  /// start of a word, or follows a keyword left on the line earlier.
  void _startMention() {
    final host = widget.host;
    if (host == null || _marks.base != _marks.extent) return;
    final triggers = {...host.mentions.keys, if (host.commands.isNotEmpty) _at};
    final at = _marks.extent;
    final lineStart = _text.lineStart(_text.lineAt(at));
    bool starts(int start) => start == lineStart || !_wordCharacter.hasMatch(_text.substring(start - 1, start));
    for (final trigger in triggers) {
      final start = at - trigger.length;
      if (start < lineStart || _text.substring(start, at) != trigger || !starts(start)) continue;
      _dismissed = null;
      _mention = (trigger: trigger, start: start);
      _followMention();
      return;
    }
    final start = _text.substring(lineStart, at).lastIndexOf(_at) + lineStart;
    if (start < lineStart || start == _dismissed || !starts(start)) return;
    if (commandIn(host.commands, _text.substring(start + _at.length, at)) == null) return;
    _mention = (trigger: _at, start: start);
    _followMention();
  }

  /// What starts a keyword of the host.
  static const _at = '@';

  /// The longest a search goes before its trigger is something left
  /// behind, and the longest a question is.
  static const _maxSearch = 60, _maxQuestion = 2000;

  static final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Asks the host what to propose for the text typed after the trigger,
  /// and ends the mention when the caret leaves it. A keyword written
  /// there is searched in; one that answers takes the rest of the line as
  /// its question.
  void _followMention() {
    final m = _mention;
    final host = widget.host;
    if (m == null || host == null || _asking != null) return;
    final from = m.start + m.trigger.length;
    final at = _marks.extent;
    if (_marks.base != at || at < from || _text.substring(m.start, from) != m.trigger) {
      _endMention();
      return;
    }
    final typed = _text.substring(from, at);
    final command = m.trigger == _at ? commandIn(host.commands, typed) : null;
    final longest = command?.answer == null ? _maxSearch : _maxQuestion;
    if (typed.contains('\n') || typed.startsWith(' ') || typed.length > longest) {
      _endMention();
      return;
    }
    if (command != null && command.answer != null) {
      _query = null;
      _searches++;
      final question = _question(m.start, command);
      setState(() {
        _command = command;
        _typed = question;
        _searching = _searchFailed = false;
        _chosen = 0;
        _found = [
          if (question.isNotEmpty)
            Proposal(
              widget.strings.ask,
              () => _ask(command),
              detail: widget.strings.askHint,
              icon: const Icon(Icons.keyboard_return, size: 20),
            ),
        ];
      });
      _mentionMenu.show();
      return;
    }
    if (typed == _query) return;
    _query = typed;
    final search = ++_searches;
    final keywords = [
      if (m.trigger == _at && command == null)
        for (final c in commandsStarting(host.commands, typed))
          Proposal('$_at${c.keyword}', () => _writeKeyword(c), icon: Icon(c.icon ?? Icons.alternate_email, size: 20)),
    ];
    final rest = command == null ? typed : typed.substring(typed.indexOf(' ') + 1).trimLeft();
    final source = command == null ? host.mentions[m.trigger] : command.search;
    setState(() {
      if (command != _command) _found = const [];
      _command = command;
      _typed = command == null ? '' : rest;
      _searching = command != null;
      _searchFailed = false;
    });
    if (command != null) _mentionMenu.show();
    (source?.call(rest) ?? Future.value(const <Mention>[])).then(
      (found) => _proposed(search, [
        ...keywords,
        for (final f in found) Proposal(f.text, () => _pickMention(f), detail: f.detail, icon: f.icon),
      ]),
      onError: (Object _) => _proposed(search, keywords, failed: true),
    );
  }

  void _proposed(int search, List<Proposal> found, {bool failed = false}) {
    if (search != _searches || !mounted) return;
    setState(() {
      _found = found.take(8).toList();
      _chosen = 0;
      _searching = false;
      _searchFailed = failed;
    });
    _found.isEmpty && _command == null && !failed ? _mentionMenu.hide() : _mentionMenu.show();
  }

  /// Ends the mention being typed; one whose answer is on its way stays
  /// until [_stopAsking].
  void _endMention() {
    if (_mention == null || _asking != null) return;
    _mention = null;
    _query = null;
    _command = null;
    _typed = '';
    _found = const [];
    _searching = _searchFailed = false;
    _searches++;
    _mentionMenu.hide();
  }

  /// Writes the link to [m] in place of the trigger and the text after it,
  /// followed by a space.
  void _pickMention(Mention m) {
    final mention = _mention;
    if (mention == null) return;
    final end = _marks.extent;
    _endMention();
    final next = end < _text.length ? _text.substring(end, end + 1) : '';
    _replace(mention.start, end, next == ' ' ? linkMarkdown(m.text, m.uri) : '${linkMarkdown(m.text, m.uri)} ');
  }

  /// Completes the keyword being typed, which what is typed next is for.
  void _writeKeyword(Command command) {
    final mention = _mention;
    if (mention == null) return;
    final written = '$_at${command.keyword} ';
    if (!_edit(mention.start, _marks.extent, written)) return;
    // the edit pushed the start of the mention past what it wrote there
    _mention = mention;
    _select(mention.start + written.length);
  }

  /// What is written after the keyword at [start], up to the end of its
  /// line.
  String _question(int start, Command command) =>
      _text.substring(start + _at.length + command.keyword.length, _text.lineEnd(_text.lineAt(start))).trim();

  /// Asks [command] the question written after it, and holds the note
  /// until the answer has replaced both.
  void _ask(Command command) {
    final mention = _mention;
    if (mention == null) return;
    final end = _text.lineEnd(_text.lineAt(mention.start));
    final asking = _asking = _Asking(end);
    _found = const [];
    asking.answer =
        command.answer!(
          _question(mention.start, command),
          before: _text.substring(0, mention.start),
          after: _text.substring(end, _text.length),
        ).listen(
          (said) => said.done ? _answered(said.text) : setState(() => asking.steps.add(said.text)),
          onError: (Object _) => _stopAsking(),
          onDone: _stopAsking,
        );
    _sessionChanged();
  }

  void _answered(String text) {
    final start = _mention?.start;
    final end = _asking?.end;
    _stopAsking();
    if (start != null && end != null) _replace(start, end, text);
  }

  /// Gives up on the answer on its way, and gives the note back.
  void _stopAsking() {
    final asking = _asking;
    if (asking == null) return;
    _asking = null;
    asking.stop();
    _endMention();
    _sessionChanged();
  }

  void _chooseMention(int by) => setState(() => _chosen = (_chosen + by) % _found.length);

  Widget _mentionMenuBuilder(BuildContext context) {
    final render = _render;
    final m = _mention;
    final command = _command;
    if (render == null || !render.hasSize || m == null || _found.isEmpty && command == null && !_searchFailed) {
      return const SizedBox.shrink();
    }
    final strings = widget.strings;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final caret = render.caretRect(m.start);
    Offset local(Offset p) => overlay.globalToLocal(render.localToGlobal(p));
    return MentionMenu(
      anchor: Rect.fromPoints(local(caret.topLeft), local(caret.bottomRight)),
      found: _found,
      chosen: _chosen,
      strings: strings,
      command: command,
      typed: _typed,
      busy: _searching || _asking != null,
      note: _searchFailed
          ? strings.searchFailed
          : command?.answer != null
          ? strings.writeQuestion
          : _searching
          ? null
          : strings.noResult,
      steps: _asking?.steps,
      onCancel: _stopAsking,
    );
  }

  /// Writes [text] where the caret is, in place of what is selected.
  void insert(String text) => _replace(_marks.start, _marks.end, text);

  // pictures

  /// Gives a picture to the host, and writes it on a line of its own where
  /// the caret was. It throws what the host's upload threw.
  Future<void> insertPicture(Uint8List bytes, String name, String type) async {
    final host = widget.host;
    if (host == null || !_editable) return;
    final upload = _Upload(_marks.end);
    _uploads.add(upload);
    try {
      final uri = await host.upload(bytes, name, type);
      if (!mounted || !_editable) return;
      final at = upload.at;
      final line = _text.lineAt(at);
      final before = at > _text.lineStart(line) ? '\n' : '';
      final after = at < _text.lineEnd(line) ? '\n' : '';
      final alt = name.replaceFirst(RegExp(r'\.[^.]*$'), '');
      _replace(at, at, '$before!${linkMarkdown(alt, uri)}$after');
    } finally {
      _uploads.remove(upload);
    }
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
    _openThreadAt(_marks.extent);
    _followMention();
    _revealSelection();
    _restartBlink();
    if (reveal) _reveal(_marks.extent);
    _syncInput();
  }

  /// Shows the lines of the selection as written, when they can be edited.
  void _revealSelection() {
    final layout = _layout;
    if (layout == null) return;
    if (!_focus.hasFocus || !_editable) {
      layout.reveal(-1, -1);
      return;
    }
    final (first, last) = _syntax.revealed(_text.lineAt(_marks.start), _text.lineAt(_marks.end));
    layout.reveal(first, last);
  }

  /// Ticks or unticks the box of a task at [local], if there is one.
  bool _toggleTask(Offset local) {
    final at = _render?.taskAt(local);
    if (at == null || !_editable) return false;
    final done = _text.substring(at + 1, at + 2) != ' ';
    _edit(at + 1, at + 2, done ? ' ' : 'x');
    return true;
  }

  /// The link at [local] a click opens: on a line read as it renders, or
  /// anywhere with the command key.
  Uri? _linkAt(Offset local) {
    final host = widget.host;
    final link = _render?.linkAt(local);
    if (host == null || link == null || link.image) return null;
    final command = _apple ? HardwareKeyboard.instance.isMetaPressed : HardwareKeyboard.instance.isControlPressed;
    if (!command && !(_layout?.previewed(_text.lineAt(link.start)) ?? false)) return null;
    return linkUri(host, link.dest, wiki: link.wiki);
  }

  bool _openLink(Offset local) {
    final uri = _linkAt(local);
    if (uri == null) return false;
    widget.host!.open(uri);
    return true;
  }

  void _hover(PointerHoverEvent e) {
    final cursor = _linkAt(e.localPosition) == null ? SystemMouseCursors.text : SystemMouseCursors.click;
    if (cursor != _cursor) setState(() => _cursor = cursor);
    final uri = _pointedAt(e.localPosition);
    if (uri == _pointed) return;
    _unpoint();
    _pointed = uri;
    if (uri == null) return;
    final at = e.position;
    _resting = Timer(const Duration(milliseconds: 400), () => _showCard(uri, at, touch: false));
  }

  /// The link under [local], written or rendered, as the host knows it.
  Uri? _pointedAt(Offset local) {
    final host = widget.host;
    final link = _render?.linkAt(local);
    return host == null || link == null || link.image ? null : linkUri(host, link.dest, wiki: link.wiki);
  }

  /// Shows what the host says of [uri] near [at]. Under a pointer the card
  /// is only read, and leaves with it; under a finger it is what gets
  /// tapped, and anything else puts it away.
  bool _showCard(Uri uri, Offset at, {required bool touch}) {
    final card = mounted ? widget.host?.preview(uri) : null;
    if (card == null) return false;
    _unpoint();
    _pointed = uri;
    final placed = CustomSingleChildLayout(delegate: _CardPlace(at), child: card);
    final entry = _card = OverlayEntry(
      builder: (context) => touch
          ? Listener(
              behavior: HitTestBehavior.translucent,
              onPointerUp: (_) => WidgetsBinding.instance.addPostFrameCallback((_) => _unpoint()),
              child: placed,
            )
          : IgnorePointer(child: placed),
    );
    Overlay.of(context).insert(entry);
    return true;
  }

  void _unpoint() {
    _resting?.cancel();
    _card?.remove();
    _card?.dispose();
    _card = null;
    _pointed = null;
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
    widget.follow?.stop();
    if (_marks.composing.isValid && !_marks.composing.isCollapsed) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final command = _apple ? keys.isMetaPressed : keys.isControlPressed;
    final word = _apple ? keys.isAltPressed : keys.isControlPressed;
    if (_asking != null && e.logicalKey == LogicalKeyboardKey.escape) {
      _stopAsking();
      return KeyEventResult.handled;
    }
    if (_mention != null) {
      final picking = _found.isNotEmpty;
      switch (e.logicalKey) {
        case LogicalKeyboardKey.arrowDown when picking:
          _chooseMention(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp when picking:
          _chooseMention(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter || LogicalKeyboardKey.tab when picking:
          _found[_chosen].take();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          _dismissed = _mention?.start;
          _endMention();
          return KeyEventResult.handled;
      }
    }
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
        if (_tableMove(columns: shift ? -1 : 1)) break;
        if (!_editable) return KeyEventResult.ignored;
        _indent(outdent: shift);
      case LogicalKeyboardKey.keyA when command:
        _select(0, extent: _text.length, reveal: false);
      case LogicalKeyboardKey.keyC when command:
        unawaited(_copy());
      case LogicalKeyboardKey.keyX when command && _editable:
        unawaited(_copy(cut: true));
      case LogicalKeyboardKey.keyV when command && _editable:
        // left to the browser, which then tells the page to paste
        if (_unwatchPaste != null) return KeyEventResult.ignored;
        unawaited(_paste());
      case LogicalKeyboardKey.keyZ when command:
        _travel(back: !shift);
      case LogicalKeyboardKey.keyY when command && !_apple:
        _travel(back: false);
      case LogicalKeyboardKey.keyM when command && keys.isAltPressed && widget.comments != null:
        comment();
      default:
        return KeyEventResult.ignored;
    }
    _touch.value = false;
    return KeyEventResult.handled;
  }

  // the platform's input

  void _focusChanged() {
    if (_focus.hasFocus) {
      _openInput();
    } else {
      _closeInput();
      _menu.remove();
      _endMention();
    }
    _revealSelection();
    _restartBlink();
  }

  void _openInput() {
    if (!_editable || !_focus.hasFocus || (_input?.attached ?? false)) return;
    _platform = null;
    _input = TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: TextInputType.multiline,
        allowedMimeTypes: widget.host == null ? const [] : const ['image/png', 'image/jpeg', 'image/gif', 'image/webp'],
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
  void insertContent(KeyboardInsertedContent content) {
    final data = content.data;
    if (data == null) return;
    final name = Uri.tryParse(content.uri)?.pathSegments.lastOrNull ?? 'picture';
    insertPicture(data, name, content.mimeType).ignore();
  }

  // pointers

  void _pointerDown(PointerDownEvent e) {
    widget.follow?.stop();
    _menu.remove();
    _unpoint();
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons == kPrimaryMouseButton &&
        (_toggleTask(e.localPosition) || _openLink(e.localPosition))) {
      return;
    }
    _focus.requestFocus();
    _touch.value = e.kind != PointerDeviceKind.mouse;
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
    if (render == null || _toggleTask(d.localPosition)) return;
    if (_linkAt(d.localPosition) case final uri?) {
      if (!_showCard(uri, d.globalPosition, touch: true)) widget.host!.open(uri);
      return;
    }
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

  /// Shows the menu of the selection: over it, or under it and its handles
  /// when there is no room above. [global] is where a mouse asked for it.
  void _showMenu(Offset global) {
    final s = _marks;
    final selected = s.base != s.extent;
    var anchors = TextSelectionToolbarAnchors(primaryAnchor: global);
    final render = _render;
    if (_touch.value && render != null) {
      final top = render.localToGlobal(render.caretRect(s.start).topLeft);
      final bottom = render.localToGlobal(render.caretRect(s.end).bottomLeft);
      final x = (top.dx + bottom.dx) / 2;
      anchors = TextSelectionToolbarAnchors(primaryAnchor: Offset(x, top.dy), secondaryAnchor: Offset(x, bottom.dy + 32));
    }
    _menu.show(
      context: context,
      contextMenuBuilder: (context) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: [
          if (selected && _editable)
            ContextMenuButtonItem(type: ContextMenuButtonType.cut, onPressed: () => _menuDone(_copy(cut: true))),
          if (selected) ContextMenuButtonItem(type: ContextMenuButtonType.copy, onPressed: () => _menuDone(_copy())),
          if (_editable) ContextMenuButtonItem(type: ContextMenuButtonType.paste, onPressed: () => _menuDone(_paste())),
          if (widget.comments != null && _editable && selected)
            ContextMenuButtonItem(
              type: ContextMenuButtonType.custom,
              label: widget.strings.comment,
              onPressed: () => _menuDone(Future(comment)),
            ),
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
        final editor = Focus(
          focusNode: _focus,
          autofocus: widget.autofocus,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _cursor,
            onExit: (_) => _unpoint(),
            child: Scrollbar(
              controller: _scroll,
              child: Scrollable(
                controller: _scroll,
                axisDirection: AxisDirection.down,
                viewportBuilder: (context, offset) => Listener(
                  onPointerDown: _pointerDown,
                  onPointerSignal: (_) {
                    widget.follow?.stop();
                    _unpoint();
                  },
                  onPointerHover: _hover,
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
        return OverlayPortal(
          controller: _mentionMenu,
          overlayChildBuilder: _mentionMenuBuilder,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // among the text fields of the page: a click here is otherwise
              // a click outside for the one being left, which takes the focus
              // back as the editor asks for it
              TextFieldTapRegion(child: editor),
              ValueListenableBuilder(
                valueListenable: _touch,
                builder: (context, touch, _) => touch
                    ? SelectionHandles(
                        marks: _marks,
                        scroll: _scroll,
                        note: () => _render,
                        onMoved: (base, extent) => _select(base, extent: extent),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A question being answered: where it ends in the note, the answer on its
/// way and what it said it was doing so far.
class _Asking {
  _Asking(this.end);

  int end;
  StreamSubscription<Answer>? answer;
  final steps = <String>[];

  void stop() => unawaited(answer?.cancel());
}

class _Upload {
  _Upload(this.at);

  int at;
}

/// Places the card of a link under where it was pointed at, or over it
/// when there is no room under, and inside the screen.
class _CardPlace extends SingleChildLayoutDelegate {
  const _CardPlace(this.target);

  final Offset target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      positionDependentBox(size: size, childSize: childSize, target: target, preferBelow: true, verticalOffset: 14);

  @override
  bool shouldRelayout(_CardPlace old) => old.target != target;
}
