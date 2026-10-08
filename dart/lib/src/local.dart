import 'dart:async';
import 'dart:convert';

import 'package:trame/trame.dart';

import 'editor.dart' show noteBody;

/// The session of a note the app alone holds: no hub behind it and nobody
/// else in it. Every edit is confirmed at once, and what becomes of the text
/// — [noteText] — is the app's to decide. Its owner disposes of it.
DocSession localNote(String markdown) => DocSession((_) async => _LocalLink(markdown))..start();

/// The Markdown of the note [session] edits, empty until it is loaded.
String noteText(DocSession session) {
  final text = session.document[noteBody]?.text?.text ?? '';
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

/// What the hub answers a single client: the note as it was given, then an
/// acknowledgement of each edit.
class _LocalLink implements DocTransport {
  _LocalLink(this._markdown) {
    _frame({'t': 'hello', 'sid': 1, 'id': '', 'name': '', 'epoch': 'local', 'v': 0, 'saved': 0, 'peers': const <Object>[]});
  }

  final String _markdown;
  var _version = 0;
  final _incoming = StreamController<String>();

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Stream<String> get messages => _incoming.stream;

  void _frame(Map<String, Object?> frame) => _incoming.add(jsonEncode(frame));

  @override
  void send(String data) {
    final msg = jsonDecode(data) as Map<String, Object?>;
    switch (msg['t']) {
      case 'sync':
        final body = Node(id: noteBody, type: 'text', key: 'V', text: Delta([Op.insert('$_markdown\n')]));
        _frame({'t': 'doc', 'v': _version, 'ack': 0, 'd': Edit([Change.create(body)]).toJson()});
      case 'op':
        _version++;
        _frame({'t': 'ack', 'n': msg['n'], 'v': _version});
        _frame({'t': 'saved', 'v': _version});
    }
  }

  @override
  Future<void> close() => _incoming.close();
}
