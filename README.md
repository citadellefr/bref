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

> Bref is at its beginning: notes are edited together in live preview, the
> syntax of the lines being edited shown as written, with mentions, links and
> pictures your app provides. Comments, math, charts and diagrams come next.

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
hub := bref.NewHub(store, bref.Options{
	OnLinks: func(key string, added []bref.Link) {
		// [@Alice](user:42) was written by added[i].By: tell Alice
	},
})

// in the handler of an authorized WebSocket
err := hub.Serve(ctx, conn, "notes/meeting.md", trame.Peer{ID: "42", Name: "Alice", Client: clientID})
```

A hub that serves other documents too takes `bref.Format(opt)` as the format
of its notes. The protocol is [trame's](https://github.com/citadellefr/trame#protocol):
a note is a single node, `body`, whose text is the file's, one paragraph per
line. Its characters carry one attribute, `by`, the ID of who wrote them,
which the hub sets and never writes in the file.

`OnLinks` is told, as a note is saved, of the links, mentions and pictures
added since the last save, each with who wrote it: to notify people
mentioned, or to index the links between notes.

## Client

```dart
final session = DocSession(
  webSocketConnector((clientId) async => Uri.parse('wss://example.com/note?client=$clientId')),
)..start();

BrefEditor(session: session);
```

The editor shows the note as it reads, the Markdown of the lines being edited
shown as it is written, with the carets and selections of everyone else;
`preview: false` shows all of it as written. It keeps the keys of
text editors, goes on with lists and quotes on Enter, indents them with Tab,
and undoes this person's edits only.

What links stand for is the app's, through a `BrefHost`:

```dart
class Host extends BrefHost {
  @override
  Map<String, MentionSource> get mentions => {
    '@': (query) async => [for (final u in await people(query)) Mention('@${u.name}', Uri.parse('user:${u.id}'))],
  };

  @override
  Set<String> get schemes => {'user', 'doc'};

  @override
  Future<Uri> upload(Uint8List bytes, String name, String type) => drive.put(bytes, name, type);

  @override
  ImageProvider? image(Uri uri) => uri.scheme == 'doc' ? NetworkImage(drive.url(uri)) : null;

  @override
  Future<LinkLabel?> describe(Uri uri) async => uri.scheme == 'user' ? LinkLabel(await nameOf(uri.path)) : null;

  @override
  void open(Uri uri) => router.go(uri);
}

BrefEditor(session: session, host: Host());
```

Typing `@` proposes what the host has, written as a standard link:
`[@Alice](user:42)`. Lines read as they render show the pictures the host
gives and links as it labels them; a click opens a link, with the command
key on the lines being edited. A link to a scheme that is neither the web's
nor the host's is never opened. The host gives pictures from its own
clipboard or drops to `BrefEditorState.insertPicture`, which uploads them
and writes them where the caret was; keyboards that insert pictures go the
same way. `file:` is best avoided as a scheme of the host: Dart reads
`file:9` as `file:///9`.

## Markdown

Package `md` reads Markdown as CommonMark and GitHub do, with front matter,
`$math$`, `==highlights==` and `[[wiki links]]`. Each node knows where it lies
in the source and which of its characters are syntax:

```go
doc := md.Parse(src)
html := md.HTML(doc) // raw HTML shown as text
```

The Dart editor reads notes with the same parser, written again in Dart and
checked against the trees of Go in `testdata/md/vectors.json`
(`go test ./md -update` writes them).

## Tests

```sh
go test -race ./...
go test -run '^$' -bench Keystroke .
(cd dart && flutter test)
(cd dart && BREF_BENCH=1 flutter test test/bench_test.dart)
```
