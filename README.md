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
> pictures your app provides, comments, tables, math and charts. Diagrams
> come next.

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

  // `@tasks bread` searches what to mention, `@assistant sum this up`
  // answers in place of the question
  @override
  List<Command> get commands => [
    Command('tasks', search: (query) async => [for (final t in await tasks(query)) Mention('@${t.title}', Uri.parse('task:${t.id}'))]),
    Command('assistant', answer: (question, {required before, required after}) => assistant.write(question, before, after)),
  ];

  @override
  Set<String> get schemes => {'user', 'task', 'doc'};

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

## Blocks

Typing `/` at the start of a line or after a space proposes what the editor
writes by itself — headings, lists, a table, a callout, a formula, a chart —
narrowed by what is typed after it. The one chosen is written as plain
Markdown, on lines of its own when it needs them, with what is to be typed
over selected. `BrefEditor.blocks` replaces the list: `blocks(strings)`
filtered, to leave out the ones marked `figure` where notes are read by
something that does not draw them, or empty for no menu.

## Math

`$x^2$` in a line and `$$` around lines of their own are set as TeX sets
them, by Bref itself: fractions, roots, scripts and limits, delimiters that
grow (`\left`, `\right`, `\big`), accents, braces and arrows that stretch,
matrices, `aligned` and `cases`, the alphabets (`\mathbb`, `\mathcal`,
`\mathfrak`, `\mathbf`…), text, colors. A block shows its formula alone, and
under its source while the caret is in it; a command Bref does not know is
shown as written, in red, and the rest of the formula is set around it.

The glyphs and their measures are those of
[Latin Modern Math](https://www.gust.org.pl/projects/e-foundry/lm-math),
shipped with the package under the GUST Font License
(`dart/fonts/GUST-FONT-LICENSE.txt`) and read by Bref: its outlines, and the
`MATH` table that says how tall a fraction stands and how a brace is built.
The file is read when a note first shows math.

## Charts

A block of code that says `chart` is drawn as one: lines of `key: value`,
then a table whose first column names the rows and each other column is a
series. A reader without Bref shows the block, which stays readable.

````
```chart
type: bar
title: Sales
| Month | Paris | Lyon |
| --- | --- | --- |
| January | 12 | 8 |
| February | 15 | 11.5 |
```
````

`type` is `bar` (the default), `line`, `area`, `pie` or `scatter`; `title`,
`x` and `y` name the chart and its axes, `stacked: true` puts bars and areas
one over the other. Numbers are read with a point or a comma, and the axes
write them the same way; a cell that is not a number is a hole. When the
first column holds numbers, lines and points are placed by them. A block
with no data to draw stays as written. `BrefTheme.series` are the colors.

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
