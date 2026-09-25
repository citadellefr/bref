# Bref

**Word, Excel and PowerPoint documents for Go servers and Flutter apps.**

Bref opens, edits and saves `.docx`, `.xlsx` and `.pptx` files natively, with
real-time collaboration and an interface that feels familiar to Microsoft
Office users. It is developed by [Citadelle](https://github.com/citadellefr),
where it replaces a LibreOffice-based editor, and is released under the MIT
license.

> Bref is in early development. Nothing here is ready for use yet.

## Principles

- **Nothing is lost.** Whatever Bref does not understand in a file is written
  back exactly as it was read. Opening and saving a document without editing it
  gives back the same document.
- **The server owns the file.** The Go package reads and writes Office Open
  XML; the Flutter package only ever sees a document model.
- **Small servers.** No dependency outside the Go standard library, and budgets
  measured in benchmarks.

## Packages

| Package | Role |
|---|---|
| [`bref`](.) | The hub: one room per open document, edits rebased and relayed to everyone connected, saves after a pause. Serves plain text files (`.txt`) for now. |
| [`dart`](dart) | The Flutter package: the session with the hub, the same `ot` algorithms, and the editors. |
| [`ot`](ot) | Edits and how concurrent edits are reconciled: text is a flow of characters and paragraph marks, changed by deltas. The Dart package runs the same algorithms, checked against shared vectors. |
| [`opc`](opc) | The zip container of Office documents: parts, content types, relationships. Untouched parts are copied without being decompressed. Guards against zip bombs, unsafe paths and forged sizes. |
| `internal/xmltok` | An XML tokenizer that allocates nothing per token and keeps the exact bytes of every element, several times faster than `encoding/xml` and checked against it. |
| `internal/prototype/pagination` | A measure, not a feature: how often a page laid out with metric-compatible free fonts ends where Word ended it. |
| `internal/xmlcanon` | Whether two XML parts mean the same thing to Office, whatever their prefixes, quoting or layout: how rewritten parts are checked. |

## Protocol

A client connects over a WebSocket the host application has authorized, and
exchanges JSON frames with the hub:

| From | Frame | Meaning |
|---|---|---|
| hub | `hello` | who the client is (`sid`), who else is there, which stay in memory of the document (`epoch`) |
| client | `sync` | the `epoch` and revision `v` of the document it holds, if any |
| hub | `doc` | the whole document at revision `v`, and `ack`, the last edit of this client applied |
| hub | `op`, `ack` … `ready` | or else the edits it missed since `v`, its own acknowledged |
| client | `op` | an edit `d`, numbered `n`, made on revision `v` |
| hub | `op` | someone's edit, rebased, with the revision `v` it made |
| hub | `ack`, `nack` | the client's edit `n` applied as revision `v`, or refused and why |
| both | `eph` | cursors and selections, relayed as they are |
| hub | `join`, `leave`, `saved`, `error` | people coming and going, saves and why one failed |

A client keeps one edit in flight and composes the next ones until it is
acknowledged.

## Tests

```sh
corpus/fetch.sh   # test files from Apache POI, LibreOffice, python-docx and python-pptx
go test -race ./...
go test ./ot -run Vectors -update   # after changing the ot algorithms
(cd dart && flutter test)          # replays the same vectors
go test ./opc -run '^$' -fuzz FuzzOpen
go test ./internal/xmltok -run '^$' -fuzz FuzzSameAsEncodingXML
```

The corpus is downloaded from pinned commits and never committed.

The corpus tests write the packages they rewrite to `$BREF_OUT`, which CI then
checks with the Open XML SDK: a rewrite must add no error to those of the
original file.

```sh
BREF_OUT=/tmp/out go test ./... -run Corpus
dotnet run --project tools/validate -- corpus/files /tmp/out
```
