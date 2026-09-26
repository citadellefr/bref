# Changelog

## Unreleased

- `ot`: documents are trees of nodes with attributes and text, changed by
  edits; the hub, its protocol and plain text files use them.
- `ot`: no edit deletes the final paragraph mark of a flow.
- `internal/xmldom`: elements that keep their bytes, patched rather than rebuilt.
- `drawingml`: colors, fills, lines, geometries, positions, paragraph, run
  and body properties as JSON; text bodies as flows and back.
- `tools/presets`: the preset shapes of DrawingML, for Go and Dart.
- `pptx`: presentations read into trees and written back, only the parts
  that changed; slides added, copied, moved and deleted; notes.
- `bref`: the hub serves presentations and their pictures (`Hub.Media`).
- `pptx`: pictures in backgrounds and theme fills; trees of test
  presentations in `testdata/pptx` for the Dart package.
- `tools/validate`: edited documents may lose parts, those added must be
  valid.
- corpus: Impress test documents from LibreOffice.

## 0.1.0 — 2026-09-26

- `opc`: read and write OPC packages, keeping untouched parts byte for byte.
- `internal/xmltok`: allocation-free XML tokenizer for document parts.
- `internal/xmlcanon`: canonical comparison of XML parts.
- `opc`: `[Content_Types].xml` keeps the order of its rules when rewritten.
- `tools/validate`: Open XML SDK validation of rewritten packages, in CI.
- `opc`: an entry renamed from backslashes takes the spelling of its override.
- corpus: Writer test documents from LibreOffice.
- `internal/prototype/pagination`: measures how closely Word's page breaks are reproduced.
- `ot`: text flows, deltas, composition and transformation, with vectors for the Dart package.
- `bref`: the hub, which orders, rebases and relays edits, catches up reconnecting clients and saves plain text files.
- `dart`: the Flutter package, with the session and a plain text editor.
