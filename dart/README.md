# bref

The Flutter client of [Bref](https://github.com/citadellefr/bref): Office
documents edited together in real time, offline edits included, against the
Go server.

```dart
import 'package:bref/bref.dart';

final session = DocSession(
  webSocketConnector((clientId) async => Uri.parse('wss://example.com/doc?client=$clientId')),
)..start();

PlainTextEditor(session: session, node: 'body');
// or, for a presentation, with its pictures fetched from the host
PresentationEditor(session: session, media: (name) => fetchPicture(name));
```

A session shows local edits at once and rebases them over those of others;
`undo` and `redo` revert this person's edits only. See the
[repository README](https://github.com/citadellefr/bref#readme) for the
server side and the protocol.
