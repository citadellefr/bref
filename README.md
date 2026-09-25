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
| [`opc`](opc) | The zip container of Office documents: parts, content types, relationships. Untouched parts are copied without being decompressed. Guards against zip bombs, unsafe paths and forged sizes. |
| `internal/xmltok` | An XML tokenizer that allocates nothing per token and keeps the exact bytes of every element, several times faster than `encoding/xml` and checked against it. |
| `internal/xmlcanon` | Whether two XML parts mean the same thing to Office, whatever their prefixes, quoting or layout: how rewritten parts are checked. |

## Tests

```sh
corpus/fetch.sh   # test files from Apache POI, python-docx and python-pptx
go test -race ./...
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
