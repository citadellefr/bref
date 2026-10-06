# Changelog

## Unreleased

- Comments and authorship, kept beside the file when the host's store is a
  `trame.MetaStore`: threads are `thread` nodes holding `msg` nodes, the
  passage of a thread carries the attribute `c.<thread>`. The server dates
  messages and only their author edits or deletes them. When the file was
  changed by someone else, passages are found again by their words.
- Dart: `BrefComments` (the threads of a note, the one open, the passage
  being commented, who-wrote-what on or off), `CommentsPane` beside the
  editor, `BrefEditor(comments:, strings:)` marking the passages and opening
  a thread at the caret; Ctrl+Alt+M or the selection menu starts a comment.
  `BrefStrings` holds the words the editor says.
- `Options.OnSave` is given each version of a note with those who edited it.

## 0.8.0 — 2026-10-05

- On trame 0.3.0. The characters of a note carry `by`, the ID of who wrote
  them: the editor signs what it writes, and the hub signs again what was
  not signed by its author, such as text whose deletion is undone.
  `bref.NewHub` takes `bref.Options`; `bref.Open` gives way to
  `bref.Format(opt)`.
- `Options.OnLinks` is told, as a note is saved, of the links, mentions and
  pictures added since the last save, each with who wrote most of it.
- `md.Links` lists the links and pictures of a document, `md.Plain` the
  text of a node; `md.Renderer` renders HTML whose links and pictures lead
  where the host says.
- Dart: `BrefHost`, what the app provides. Typing a trigger, `@` or `[[`,
  proposes what the host has, written `[@Alice](user:42)`. Lines read as
  they render show the host's pictures and its labels of links; a click
  opens a link where the host goes, never to a scheme it does not know.
  `BrefEditorState.insertPicture` uploads a picture and writes it where the
  caret was.

## 0.7.0 — 2026-10-05

- The Go package serves `.md` notes on trame's hub: a note is its text, written
  back as it was read; its characters carry no attributes.
- Dart: `BrefEditor` edits the Markdown source, marked as it is typed
  (headings, emphasis, code, links, lists, tasks, quotes, tables, math, fenced
  blocks and front matter), with the carets of others, the keys of text
  editors, lists and quotes going on with Enter, and only the lines in view
  laid out. On touch screens, a long press selects a word whose ends move
  with the platform's handles, under a menu kept clear of them.
- Package `md`, in Go and in Dart: Markdown read as CommonMark and GitHub
  read it, with front matter, math, highlights and wiki links; each node
  knows where it lies and which of its characters are syntax. Both parsers
  pass the examples of the two specifications and find the same trees,
  checked against `testdata/md/vectors.json`.
- Dart: the editor reads its note with this parser, again only from the
  last line before an edit where nothing was open. Live preview, on by
  default: lines read as they render, their syntax hidden, bullets, task
  boxes, quote bars and rules drawn, fences and heading underlines folded,
  but for the lines being edited, shown as written. A click on a task box
  ticks it.

Versions 0.1.0 to 0.6.0 of `github.com/citadellefr/bref` were those of
L'Office, now `github.com/citadellefr/loffice`.
