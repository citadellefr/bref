# Changelog

## Unreleased

- `Tree` and `Edit`: documents as trees of nodes, as the Go package `ot` has
  them; `DocSession` edits trees, selections name the node they are in.
- Undoing a deletion brings the nodes back under new ids.
- Drawing: the geometry of the 187 preset shapes and custom ones, colors
  resolved against themes as Office does, fills, lines and arrowheads.
- Presentations: slides drawn as PowerPoint does, what they inherit from
  their layout and master included; text laid out paragraph by paragraph
  with bullets, numbering, spacing and autofit, in metric-compatible fonts.

## 0.1.0 — 2026-09-26

- `Delta`: text flows and their edits, the algorithms of the Go package `ot`,
  checked against its vectors.
- `DocSession`: the link to the hub, one edit in flight, offline edits rebased
  on reconnection, undo of one's own edits.
- `PlainTextEditor`: plain text documents, with the selections of others.
