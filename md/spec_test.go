package md

import (
	"encoding/json"
	"os"
	"testing"
)

type example struct {
	Example   int    `json:"example"`
	Section   string `json:"section"`
	Extension string `json:"extension"`
	Markdown  string `json:"markdown"`
	HTML      string `json:"html"`
}

func readExamples(t testing.TB, name string) []example {
	t.Helper()
	data, err := os.ReadFile("../testdata/md/" + name)
	if err != nil {
		t.Fatal(err)
	}
	var examples []example
	if err := json.Unmarshal(data, &examples); err != nil {
		t.Fatal(err)
	}
	return examples
}

func rawHTML(doc *Node) string {
	w := htmlWriter{raw: true}
	w.node(doc, false)
	return w.b.String()
}

func TestCommonMark(t *testing.T) {
	for _, e := range readExamples(t, "commonmark.json") {
		if got := rawHTML(parse(e.Markdown, 0)); got != e.HTML {
			t.Errorf("example %d (%s)\n%q\ngot  %q\nwant %q", e.Example, e.Section, e.Markdown, got, e.HTML)
		}
	}
}

func TestGFM(t *testing.T) {
	for _, e := range readExamples(t, "gfm.json") {
		if got := rawHTML(parse(e.Markdown, gfm)); got != e.HTML {
			t.Errorf("example %d (%s)\n%q\ngot  %q\nwant %q", e.Example, e.Section, e.Markdown, got, e.HTML)
		}
	}
}
