import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextRange;
import 'package:trame/trame.dart';

import 'note_text.dart';

const _thread = 'thread';
const _message = 'msg';
const _anchor = 'c.';

/// One message of a thread. The server sets [by] and [at] from the
/// connection: a message is its author's alone to change.
@immutable
class CommentMessage {
  const CommentMessage({required this.id, required this.by, required this.name, required this.at, required this.text});

  final String id;

  /// The ID of its author, as the hub knows them.
  final String by;
  final String name;
  final DateTime? at;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is CommentMessage &&
      other.id == id &&
      other.by == by &&
      other.name == name &&
      other.at == at &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, by, name, at, text);
}

/// A discussion about a passage of the note.
@immutable
class CommentThread {
  const CommentThread({required this.id, required this.done, required this.messages, required this.ranges});

  final String id;

  /// Whether it was resolved.
  final bool done;
  final List<CommentMessage> messages;

  /// The passages it is about, in order: more than one when text was typed
  /// inside the passage. None when the passage was deleted.
  final List<TextRange> ranges;

  bool get orphan => ranges.isEmpty;

  /// From the start of its first passage to the end of its last.
  TextRange? get span => ranges.isEmpty ? null : TextRange(start: ranges.first.start, end: ranges.last.end);

  bool covers(int offset) => ranges.any((r) => r.start <= offset && offset < r.end);

  @override
  bool operator ==(Object other) =>
      other is CommentThread &&
      other.id == id &&
      other.done == done &&
      listEquals(other.messages, messages) &&
      listEquals(other.ranges, ranges);

  @override
  int get hashCode => Object.hash(id, done, Object.hashAll(messages), Object.hashAll(ranges));
}

/// The threads of a note, in the order they were started.
List<CommentThread> readThreads(Tree doc) {
  final nodes = [
    for (final n in doc.children('')) if (n.type == _thread) n,
  ];
  if (nodes.isEmpty) return const [];
  final ranges = <String, List<TextRange>>{};
  var at = 0;
  for (final op in doc[noteBody]?.text?.ops ?? const <Op>[]) {
    final end = at + op.length;
    for (final MapEntry(:key, :value) in op.attributes?.entries ?? const <MapEntry<String, String>>[]) {
      if (!key.startsWith(_anchor) || value.isEmpty) continue;
      final list = ranges.putIfAbsent(key.substring(_anchor.length), () => []);
      if (list.isNotEmpty && list.last.end == at) {
        list.last = TextRange(start: list.last.start, end: end);
      } else {
        list.add(TextRange(start: at, end: end));
      }
    }
    at = end;
  }
  return [
    for (final n in nodes)
      CommentThread(
        id: n.id,
        done: n.attributes['done'] == true,
        messages: [
          for (final m in doc.children(n.id))
            if (m.type == _message)
              CommentMessage(
                id: m.id,
                by: _string(m, 'by'),
                name: _string(m, 'name'),
                at: switch (m.attributes['at']) {
                  final int s => DateTime.fromMillisecondsSinceEpoch(s * 1000),
                  _ => null,
                },
                text: _string(m, 'text'),
              ),
        ],
        ranges: ranges[n.id] ?? const [],
      ),
  ];
}

String _string(Node n, String key) => switch (n.attributes[key]) {
  final String s => s,
  _ => '',
};

/// The edits of a person to the comments of a note, which the hub checks:
/// each is made by [session]'s own ID and name.
extension Comments on DocSession {
  /// Starts a thread about [start] to [end] of the note, with a first
  /// message, and returns its id; null when it cannot be made.
  String? startThread(int start, int end, String text) {
    final id = randomId();
    final ok = edit(Edit([
      Change.text(
        noteBody,
        Delta()
          ..retain(start)
          ..retain(end - start, {'$_anchor$id': '1'}),
      ),
      Change.create(Node(id: id, type: _thread, key: _lastKey(document, ''))),
      _newMessage(id, text, _lastKey(document, id)),
    ]));
    return ok ? id : null;
  }

  /// Answers [thread].
  bool reply(String thread, String text) =>
      edit(Edit([_newMessage(thread, text, _lastKey(document, thread))]));

  /// Resolves [thread], or reopens it.
  bool resolve(String thread, {bool done = true}) =>
      edit(Edit([Change.set(thread, attributes: {'done': done ? true : null})]));

  bool editMessage(String message, String text) => edit(Edit([Change.set(message, attributes: {'text': text})]));

  /// Deletes a message, and its thread when it was the only one.
  bool deleteMessage(String message) {
    final node = document[message];
    if (node == null) return false;
    final thread = node.parent;
    if (document.children(thread).length > 1) return edit(Edit([Change.delete(message)]));
    return deleteThread(thread);
  }

  /// Deletes [thread], its messages and the mark it leaves on the text.
  bool deleteThread(String thread) {
    final mark = readThreads(document).where((t) => t.id == thread).firstOrNull;
    final delta = Delta();
    var at = 0;
    for (final r in mark?.ranges ?? const <TextRange>[]) {
      delta
        ..retain(r.start - at)
        ..retain(r.end - r.start, {'$_anchor$thread': ''});
      at = r.end;
    }
    return edit(Edit([if (!delta.isEmpty) Change.text(noteBody, delta), Change.delete(thread)]));
  }

  Change _newMessage(String thread, String text, String key) => Change.create(Node(
    id: randomId(),
    type: _message,
    parent: thread,
    key: key,
    attributes: {'by': id, 'name': name, 'text': text},
  ));
}

String _lastKey(Tree doc, String parent) {
  final kids = doc.children(parent);
  return keyBetween(kids.isEmpty ? '' : kids.last.key, '');
}
