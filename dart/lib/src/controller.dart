import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextRange;
import 'package:trame/trame.dart';

import 'comments.dart';
import 'note_text.dart';

/// The comments of a note as they are now, shared by the editor and the pane
/// that lists them: the threads, which one is open, the passage a new comment
/// is being written about, and whether the note shows who wrote what.
///
/// The passages follow the text as it changes, without reading it again but
/// when an edit moves or removes a mark.
class BrefComments extends ChangeNotifier {
  BrefComments(this.session) {
    _changes = session.changes.listen(_changed);
    _scan();
  }

  final DocSession session;
  late final StreamSubscription<Edit> _changes;

  var _threads = const <CommentThread>[];
  String? _selected;
  TextRange? _draft;
  var _authorship = false;

  /// In the order they were started.
  List<CommentThread> get threads => _threads;

  /// The id of the thread whose card is open and passage is marked.
  String? get selected => _selected;

  /// The passage a new thread is being written about.
  TextRange? get draft => _draft;

  /// Whether the text shows, by color, who wrote it.
  bool get authorship => _authorship;

  void select(String? thread) {
    if (thread == _selected && _draft == null) return;
    _selected = thread;
    _draft = null;
    notifyListeners();
  }

  void startDraft(TextRange passage) {
    _selected = null;
    _draft = passage;
    notifyListeners();
  }

  void cancelDraft() {
    if (_draft == null) return;
    _draft = null;
    notifyListeners();
  }

  set authorship(bool value) {
    if (value == _authorship) return;
    _authorship = value;
    notifyListeners();
  }

  /// Starts the thread the draft was about, and opens it.
  bool post(String text) {
    final passage = _draft;
    if (passage == null || passage.isCollapsed) return false;
    final id = session.startThread(passage.start, passage.end, text);
    if (id == null) return false;
    _selected = id;
    _draft = null;
    notifyListeners();
    return true;
  }

  void _scan() {
    _threads = readThreads(session.document);
    if (_selected != null && !_threads.any((t) => t.id == _selected)) _selected = null;
    notifyListeners();
  }

  void _changed(Edit edit) {
    var rescan = false;
    var moved = false;
    for (final c in edit.changes) {
      if (c.id != noteBody) {
        rescan = true;
      } else if (c.kind != ChangeKind.text || c.text!.ops.any((op) => op.attributes != null && !op.isInsert)) {
        rescan = true;
      }
    }
    if (rescan) {
      _scan();
      return;
    }
    for (final c in edit.changes) {
      final delta = c.text!;
      if (delta.ops.every((op) => op.isRetain)) continue;
      moved = true;
      _threads = [
        for (final t in _threads)
          CommentThread(
            id: t.id,
            done: t.done,
            messages: t.messages,
            ranges: _follow(t.ranges, delta),
          ),
      ];
      if (_draft case final d?) _draft = _follow([d], delta).firstOrNull ?? TextRange.collapsed(d.start);
    }
    if (moved) notifyListeners();
  }

  /// Where [ranges] are after [delta]: text inserted at an edge is outside.
  static List<TextRange> _follow(List<TextRange> ranges, Delta delta) => [
    for (final r in ranges)
      if (TextRange(
        start: delta.transformPosition(r.start, thisFirst: false),
        end: delta.transformPosition(r.end, thisFirst: true),
      ) case final moved when !moved.isCollapsed)
        moved,
  ];

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }
}
