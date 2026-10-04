package bref

import (
	"strings"
	"testing"

	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/ot"
)

// BenchmarkKeystroke measures what applying a keystroke costs the hub in a
// note of 1 MB, of lines or of a single paragraph: a character typed, then
// deleted, so that the note keeps its size.
func BenchmarkKeystroke(b *testing.B) {
	for _, c := range []struct{ name, line string }{
		{"lines", strings.Repeat("lorem ipsum ", 8) + "\n"},
		{"paragraph", strings.Repeat("lorem ipsum ", 8)},
	} {
		b.Run(c.name, func(b *testing.B) {
			doc, f, err := Open("b.md", []byte(strings.Repeat(c.line, 1<<20/len(c.line))))
			if err != nil {
				b.Fatal(err)
			}
			middle := doc.Node(Body).Text.Len() / 2
			keys := []ot.Edit{
				{{Op: ot.OpTxt, ID: Body, Text: ot.Delta{{Retain: middle}, {Insert: "a"}}}},
				{{Op: ot.OpTxt, ID: Body, Text: ot.Delta{{Retain: middle}, {Delete: 1}}}},
			}
			b.ReportAllocs()
			for i := 0; b.Loop(); i++ {
				e := keys[i%2]
				if err := f.Check(doc, e, trame.Peer{}); err != nil {
					b.Fatal(err)
				}
				if err := doc.Apply(e); err != nil {
					b.Fatal(err)
				}
			}
		})
	}
}
