import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ot/delta.dart';
import 'ot/diff.dart';

/// The text link to the server, behind an interface so that sessions can be
/// tested without one.
abstract interface class DocTransport {
  Stream<String> get messages;
  int? get closeCode;
  String? get closeReason;
  void send(String data);
  Future<void> close();
}

/// Opens a transport for the session whose client id is given; called again
/// on every reconnection.
typedef DocConnector = Future<DocTransport> Function(String clientId);

/// A connector over WebSocket. [url] is asked again on every connection, so
/// it may carry a short-lived ticket.
DocConnector webSocketConnector(Future<Uri> Function(String clientId) url) => (clientId) async {
  final channel = WebSocketChannel.connect(await url(clientId));
  await channel.ready;
  return _WebSocketTransport(channel);
};

class _WebSocketTransport implements DocTransport {
  _WebSocketTransport(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<String> get messages =>
      _channel.stream.map((m) => m is String ? m : utf8.decode(m as List<int>));

  @override
  int? get closeCode => _channel.closeCode;

  @override
  String? get closeReason => _channel.closeReason;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async => _channel.sink.close();
}

enum DocStatus { connecting, online, offline, closed }

/// Why the server ended the session: the document could not be opened, or
/// access to it was withdrawn. [reason] is the server's own words.
class DocClosed implements Exception {
  const DocClosed(this.code, this.reason);

  final int code;
  final String reason;

  @override
  String toString() => reason;
}

class DocPeer {
  DocPeer._(this.sid, this.id, this.name, this.readOnly);

  final int sid;
  final String id;
  final String name;
  final bool readOnly;

  (int, int)? _selection;

  /// Where the peer's selection is, base then extent, if it is in the
  /// document.
  (int, int)? get selection => _selection;
}

/// One person's connection to a document: keeps [document] in step with the
/// server, sends local edits, reconnects when the link drops and keeps the
/// history [undo] and [redo] walk through.
///
/// Local edits show at once. One is in flight to the server at a time; the
/// next ones wait composed, offline included, and all of them are rebased
/// over the edits of others as those arrive.
class DocSession extends ChangeNotifier {
  DocSession(this._connect, {String? clientId}) : clientId = clientId ?? randomId();

  static const _historyLimit = 500;
  static const _typingPause = Duration(milliseconds: 800);
  static const _presenceEvery = Duration(milliseconds: 50);
  static const _backoff = [1, 2, 5, 10, 20, 30];

  final DocConnector _connect;
  final String clientId;

  /// Notifies selection changes of peers, far more frequent than the others.
  final Listenable presence = _Presence();

  final _peers = <int, DocPeer>{};
  final _undo = <Delta>[];
  final _redo = <Delta>[];
  final _changes = StreamController<Delta>.broadcast(sync: true);
  final _rejections = StreamController<String>.broadcast();

  DocStatus _status = DocStatus.connecting;
  Object? _failure;
  String? _saveError;
  var _readOnly = false;
  var _running = false;
  var _disposed = false;
  var _attempt = 0;
  var _savedVersion = 0;
  var _ackVersion = 0;
  DocTransport? _transport;
  StreamSubscription<String>? _subscription;
  Timer? _retry;

  Delta? _doc;
  Delta _confirmed = Delta();
  String? _text;
  var _rev = 0;
  String? _epoch;
  String? _joined;
  var _synced = false;
  var _n = 0;
  Delta? _inflight;
  var _pending = 0;
  var _sent = false;
  Delta? _buffer;
  DateTime? _lastTyping;

  (int, int)? _selection;
  var _selectionDirty = false;
  Timer? _presenceTimer;

  DocStatus get status => _status;

  /// Why the session is offline or closed, when it knows.
  Object? get failure => _failure;

  /// Why the last save failed, until one succeeds.
  String? get saveError => _saveError;

  bool get readOnly => _readOnly;

  Iterable<DocPeer> get peers => _peers.values;

  /// Whether the document arrived: nothing can be edited before.
  bool get loaded => _doc != null;

  /// The document as shown, local edits included.
  Delta get document => _doc ?? Delta();

  /// The text of the document, one line per paragraph.
  String get text {
    final doc = _doc;
    if (doc == null) return '';
    final full = _text ??= doc.text;
    return full.substring(0, full.length - 1);
  }

  /// Whether every local edit reached the file.
  bool get saved => _pending == 0 && _buffer == null && _savedVersion >= _ackVersion && _saveError == null;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  /// Every change made to [document], local or not, as it is made.
  Stream<Delta> get changes => _changes.stream;

  /// Why the server refused a local edit, which has been rolled back.
  Stream<String> get rejections => _rejections.stream;

  void start() {
    if (_running || _disposed) return;
    _running = true;
    _failure = null;
    _attempt = 0;
    unawaited(_open());
  }

  /// Reconnects now, after a close or while waiting for the next retry.
  void retry() {
    _retry?.cancel();
    _retry = null;
    if (_running && (_transport != null || _status == DocStatus.connecting)) return;
    _running = false;
    start();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _presenceTimer?.cancel();
    final transport = _transport;
    _transport = null;
    await _subscription?.cancel();
    _subscription = null;
    await transport?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    unawaited(_changes.close());
    unawaited(_rejections.close());
    (presence as _Presence).dispose();
    super.dispose();
  }

  /// Replaces the text between [start] and [end]; each "\n" in [text]
  /// starts a paragraph.
  bool replaceText(int start, int end, String text) => edit(
    Delta()
      ..retain(start)
      ..delete(end - start)
      ..insert(text),
  );

  /// Makes a local edit, which [undo] reverts. Typing is undone in bursts,
  /// as Office does.
  bool edit(Delta delta) {
    final doc = _doc;
    if (doc == null || _readOnly || delta.chop().isEmpty || delta.baseLength > doc.length) return false;
    final result = doc.compose(delta);
    if (!(result.ops.lastOrNull?.insert?.endsWith('\n') ?? false)) return false;
    final inverse = delta.invert(doc);
    final now = DateTime.now();
    final typing = _lastTyping != null && now.difference(_lastTyping!) < _typingPause && _undo.isNotEmpty;
    if (typing) {
      _undo.last = inverse.compose(_undo.last);
    } else {
      _undo.add(inverse);
      if (_undo.length > _historyLimit) _undo.removeAt(0);
    }
    _lastTyping = now;
    _redo.clear();
    _commit(delta, result);
    return true;
  }

  void undo() => _travel(_undo, _redo);

  void redo() => _travel(_redo, _undo);

  /// Applies the top of [from], skipping what the edits of others emptied,
  /// and keeps its inverse on [to].
  void _travel(List<Delta> from, List<Delta> to) {
    final doc = _doc;
    if (doc == null || _readOnly) return;
    _lastTyping = null;
    while (from.isNotEmpty) {
      final delta = from.removeLast();
      if (delta.chop().isEmpty) continue;
      to.add(delta.invert(doc));
      _commit(delta);
      return;
    }
    notifyListeners();
  }

  void _commit(Delta delta, [Delta? result]) {
    _show(delta, author: null, result: result);
    if (_pending == 0 && _synced) {
      _send(delta);
    } else {
      _buffer = _buffer?.compose(delta) ?? delta;
    }
    notifyListeners();
  }

  /// Where this person's selection is, null once it left the document.
  void select(int base, int extent) => _setSelection((base, extent));

  void unselect() => _setSelection(null);

  void _setSelection((int, int)? selection) {
    if (selection == _selection) return;
    _selection = selection;
    _selectionDirty = true;
    if (_presenceTimer?.isActive ?? false) return;
    _presenceTimer = Timer(_presenceEvery, _flushPresence);
  }

  void _flushPresence() {
    final transport = _transport;
    if (transport == null || !_synced || !_selectionDirty) return;
    _selectionDirty = false;
    final s = _selection;
    transport.send(jsonEncode({
      't': 'eph',
      'd': {'s': s == null ? null : [s.$1, s.$2]},
    }));
  }

  /// Applies a change to the document shown, and moves everything that
  /// points into it. [author] is the peer who made it, null for this one.
  void _show(Delta delta, {required int? author, Delta? result}) {
    _doc = result ?? _doc!.compose(delta);
    _text = null;
    _moved(delta, author: author);
  }

  void _moved(Delta delta, {required int? author}) {
    for (final peer in _peers.values) {
      final s = peer._selection;
      if (s == null) continue;
      final own = peer.sid == author;
      peer._selection = (
        delta.transformPosition(s.$1, thisFirst: own),
        delta.transformPosition(s.$2, thisFirst: own),
      );
    }
    _changes.add(delta);
  }

  /// Rebases the undo and redo stacks over a change others made.
  void _rebaseHistory(Delta change) {
    for (final stack in [_undo, _redo]) {
      var c = change;
      for (var i = stack.length - 1; i >= 0; i--) {
        final entry = stack[i];
        stack[i] = c.transform(entry, thisFirst: true);
        c = entry.transform(c, thisFirst: false);
      }
    }
    _lastTyping = null;
  }

  void _send(Delta delta) {
    _pending = ++_n;
    _inflight = delta;
    _transmit();
  }

  void _transmit() {
    _sent = true;
    _transport?.send(jsonEncode({'t': 'op', 'n': _pending, 'v': _rev, 'd': _inflight!.toJson()}));
  }

  void _flush() {
    final buffer = _buffer;
    if (_pending != 0 || buffer == null || !_synced) return;
    _buffer = null;
    _send(buffer);
  }

  Future<void> _open() async {
    _setStatus(DocStatus.connecting);
    final DocTransport transport;
    try {
      transport = await _connect(clientId);
    } on Object catch (error) {
      if (!_running) return;
      _failure = error;
      _setStatus(DocStatus.offline);
      _scheduleRetry();
      return;
    }
    if (!_running) {
      await transport.close();
      return;
    }
    _transport = transport;
    _synced = false;
    _sent = false;
    _subscription = transport.messages.listen(
      _receive,
      onDone: () => _dropped(transport),
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  void _dropped(DocTransport transport) {
    if (!identical(transport, _transport)) return;
    _transport = null;
    _subscription = null;
    _synced = false;
    _peers.clear();
    (presence as _Presence).changed();
    if (!_running) return;
    final code = transport.closeCode;
    if (code == 4000 || code == 4001) {
      _running = false;
      _failure = DocClosed(code!, transport.closeReason ?? '');
      _setStatus(DocStatus.closed);
      return;
    }
    _setStatus(DocStatus.offline);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    final delay = _backoff[math.min(_attempt, _backoff.length - 1)];
    _attempt++;
    _retry = Timer(Duration(seconds: delay), () {
      if (_running) unawaited(_open());
    });
  }

  void _setStatus(DocStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  void _receive(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    switch (decoded['t']) {
      case 'hello':
        _hello(decoded);
      case 'doc':
        _whole(decoded);
      case 'ready':
        _ready();
      case 'op':
        _remote(decoded);
      case 'ack':
        _acknowledged(_int(decoded['n']), _int(decoded['v']));
      case 'nack':
        _refused(_int(decoded['n']), '${decoded['error'] ?? ''}');
      case 'eph':
        _presence(decoded);
      case 'join':
        final peer = _peer(decoded['peer']);
        if (peer != null) _peers[peer.sid] = peer;
        notifyListeners();
      case 'leave':
        _peers.remove(_int(decoded['sid']));
        notifyListeners();
        (presence as _Presence).changed();
      case 'saved':
        _savedVersion = math.max(_savedVersion, _int(decoded['v']));
        _saveError = null;
        notifyListeners();
      case 'error':
        _saveError = '${decoded['error'] ?? ''}';
        notifyListeners();
    }
  }

  void _hello(Map<String, Object?> hello) {
    _readOnly = hello['ro'] == true;
    _savedVersion = _int(hello['saved']);
    _saveError = hello['error'] is String ? hello['error']! as String : null;
    _joined = hello['epoch'] is String ? hello['epoch']! as String : null;
    _peers.clear();
    for (final raw in _list(hello['peers'])) {
      final peer = _peer(raw);
      if (peer != null) _peers[peer.sid] = peer;
    }
    _transport?.send(jsonEncode({
      't': 'sync',
      if (_doc != null && _epoch != null) ...{'epoch': _epoch, 'v': _rev},
    }));
  }

  /// The whole document: the first one, or one this client could not catch
  /// up with edit by edit. Its own edits the hub has not applied are rebased
  /// over what changed, found by comparing texts.
  void _whole(Map<String, Object?> frame) {
    final flow = Delta.fromJson(frame['d']);
    if (flow == null) return;
    if (_doc == null) {
      _doc = flow;
      _text = null;
      _changes.add(flow);
    } else {
      final applied = _pending != 0 && _int(frame['ack']) >= _pending;
      var base = _confirmed;
      var mine = _buffer ?? Delta();
      if (_pending != 0) {
        if (applied) {
          base = base.compose(_inflight!);
        } else {
          mine = _inflight!.compose(mine);
        }
      }
      final theirs = diff(base.text, flow.text);
      final rebased = theirs.transform(mine, thisFirst: true);
      final shown = mine.transform(theirs, thisFirst: false);
      _pending = 0;
      _inflight = null;
      _buffer = rebased.isEmpty ? null : rebased;
      _doc = flow.compose(rebased);
      _text = null;
      _rebaseHistory(shown);
      _moved(shown, author: -1);
    }
    _confirmed = flow;
    _rev = _int(frame['v']);
    _ready();
  }

  void _ready() {
    _synced = true;
    _epoch = _joined;
    _attempt = 0;
    _failure = null;
    if (_pending != 0 && !_sent) _transmit();
    _flush();
    _selectionDirty = _selection != null;
    _flushPresence();
    _setStatus(DocStatus.online);
    (presence as _Presence).changed();
  }

  void _remote(Map<String, Object?> frame) {
    var delta = Delta.fromJson(frame['d']);
    if (delta == null || _doc == null) return;
    _confirmed = _confirmed.compose(delta);
    final inflight = _inflight;
    if (inflight != null) {
      _inflight = delta.transform(inflight, thisFirst: true);
      delta = inflight.transform(delta, thisFirst: false);
    }
    final buffer = _buffer;
    if (buffer != null) {
      _buffer = delta.transform(buffer, thisFirst: true);
      delta = buffer.transform(delta, thisFirst: false);
    }
    _rev = _int(frame['v']);
    _rebaseHistory(delta);
    _show(delta, author: _int(frame['sid']));
    notifyListeners();
    (presence as _Presence).changed();
  }

  void _acknowledged(int n, int version) {
    if (n != _pending) return;
    _confirmed = _confirmed.compose(_inflight!);
    _rev = version;
    _ackVersion = math.max(_ackVersion, version);
    _pending = 0;
    _inflight = null;
    _flush();
    notifyListeners();
  }

  /// Rolls back the edit in flight, keeping the ones made after it.
  void _refused(int n, String reason) {
    if (n != _pending) return;
    final undo = _inflight!.invert(_confirmed);
    var shown = undo;
    final buffer = _buffer;
    if (buffer != null) {
      _buffer = undo.transform(buffer, thisFirst: true);
      shown = buffer.transform(undo, thisFirst: false);
    }
    _pending = 0;
    _inflight = null;
    _rebaseHistory(shown);
    _show(shown, author: -1);
    _rejections.add(reason);
    _flush();
    notifyListeners();
  }

  void _presence(Map<String, Object?> frame) {
    final peer = _peers[_int(frame['sid'])];
    final data = frame['d'];
    if (peer == null || data is! Map<String, Object?> || !data.containsKey('s')) return;
    final s = _list(data['s']);
    peer._selection = s.length == 2 && s[0] is int && s[1] is int ? (s[0]! as int, s[1]! as int) : null;
    (presence as _Presence).changed();
  }

  static DocPeer? _peer(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    return DocPeer._(_int(raw['sid']), '${raw['id'] ?? ''}', '${raw['name'] ?? ''}', raw['ro'] == true);
  }

  static List<Object?> _list(Object? raw) => raw is List<Object?> ? raw : const [];

  static int _int(Object? raw) => raw is num ? raw.toInt() : 0;
}

class _Presence extends ChangeNotifier {
  void changed() => notifyListeners();
}

final _random = math.Random.secure();
const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

/// 16 random characters: 95 bits, enough for ids nobody coordinates.
String randomId() => String.fromCharCodes([
  for (var i = 0; i < 16; i++) _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
]);
