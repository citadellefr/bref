# Changelog

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
