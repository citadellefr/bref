# Bref

**Collaborative Markdown notes for Go servers and Flutter apps.**

Bref is a light, real-time editor for text and Markdown files, in the spirit of
Notion and Obsidian: what you write is plain Markdown, edited together and
shown as you type. It comes in two parts:

- a **Go package** that hosts the notes, on the hub of
  [trame](https://github.com/citadellefr/trame);
- a **Flutter package** that edits them, on its own or inside a call.

It is developed by [Citadelle](https://github.com/citadellefr), where it is the
default format for notes, and is released under the MIT license.

> Bref is at its beginning: notes are edited together as Markdown source,
> marked as they are typed. Live preview, mentions, pictures, comments,
> math, charts and diagrams come next.

## Principles

- **The file is the note.** A note is its Markdown text and nothing else: a
  file opened and saved without an edit is given back byte for byte, its
  line endings and byte order mark included.
- **Your host, your rules.** The server calls a two-method `Store`, over a
  connection your application has already authorized. Users, files and
  pictures are yours: Bref asks, it does not keep.
- **Nothing runs but Bref.** Markdown is drawn by Bref itself: raw HTML is
  shown as text, never interpreted, and no web view is involved.
- **Small and fast.** The Go package depends on the standard library and
  trame alone; the editor lays out only the lines in view.

## Server

```go
hub := bref.NewHub(store, trame.Options{})

// in the handler of an authorized WebSocket
err := hub.Serve(ctx, conn, "notes/meeting.md", trame.Peer{ID: "42", Name: "Alice", Client: clientID})
```

A hub that serves other documents too takes `bref.Open` as the format of its
notes. The protocol is [trame's](https://github.com/citadellefr/trame#protocol):
a note is a single node, `body`, whose text is the file's, one paragraph per
line.

## Client

```dart
final session = DocSession(
  webSocketConnector((clientId) async => Uri.parse('wss://example.com/note?client=$clientId')),
)..start();

BrefEditor(session: session);
```

The editor shows the Markdown as it is written, its marks styled as they are
typed, with the carets and selections of everyone else. It keeps the keys of
text editors, goes on with lists and quotes on Enter, indents them with Tab,
and undoes this person's edits only.

## Tests

```sh
go test -race ./...
go test -run '^$' -bench Keystroke .
(cd dart && flutter test)
(cd dart && BREF_BENCH=1 flutter test test/bench_test.dart)
```
