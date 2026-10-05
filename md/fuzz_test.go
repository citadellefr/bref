package md

import (
	"strings"
	"testing"
)

func FuzzParse(f *testing.F) {
	for _, set := range []string{"commonmark.json", "gfm.json", "bref.json"} {
		for _, e := range readExamples(f, set) {
			f.Add(e.Markdown)
		}
	}
	f.Fuzz(func(t *testing.T, src string) {
		HTML(Parse(src))
		Parse(src).Walk(func(n *Node) bool {
			if n.Start < 0 || n.Start > n.End || n.End > len(src) {
				t.Fatalf("%s at %d-%d in %q", n.Kind, n.Start, n.End, src)
			}
			for _, m := range n.Marks {
				if m.Start < 0 || m.Start > m.End || m.End > len(src) || strings.ContainsAny(src[m.Start:m.End], "\r\n") {
					t.Fatalf("%s mark %v in %q", n.Kind, m, src)
				}
			}
			return true
		})
	})
}

func BenchmarkParse(b *testing.B) {
	const line = "Un paragraphe de notes avec du **gras**, un [lien](https://x.fr) et du `code`.\n"
	var src strings.Builder
	for i := 0; src.Len() < 1<<20; i++ {
		if i%20 == 0 {
			src.WriteString("## Titre\n")
		}
		src.WriteString(line)
	}
	s := src.String()
	b.SetBytes(int64(len(s)))
	for b.Loop() {
		Parse(s)
	}
}
