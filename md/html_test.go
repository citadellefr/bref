package md

import (
	"slices"
	"testing"
)

func TestLinks(t *testing.T) {
	src := "Hi [@Alice](user:42), see [[Note|this]] and https://example.com.\n\n" +
		"> [![chart](file:9f3c)](https://example.com/big)\n\n[ref]: /there\n\n[ref] `[not](a link)`\n"
	var got []string
	for _, l := range Links(Parse(src)) {
		got = append(got, l.Kind.String()+" "+l.Dest+" "+Plain(l)+" "+src[l.Start:l.End])
	}
	want := []string{
		"link user:42 @Alice [@Alice](user:42)",
		"link Note this [[Note|this]]",
		"link https://example.com https://example.com https://example.com",
		"link https://example.com/big chart [![chart](file:9f3c)](https://example.com/big)",
		"image file:9f3c chart ![chart](file:9f3c)",
		"link /there ref [ref]",
	}
	if !slices.Equal(got, want) {
		t.Errorf("got  %q\nwant %q", got, want)
	}
}

func TestRendererURL(t *testing.T) {
	r := Renderer{URL: func(n *Node) string {
		switch {
		case n.Form == LinkWiki:
			return "/notes/" + n.Dest
		case n.Dest == "user:42":
			return ""
		case n.Dest == "file:1":
			return "javascript:alert(1)"
		}
		return n.Dest
	}}
	for _, c := range []struct{ md, html string }{
		{"[[Note|this]]", `<p><a href="/notes/Note">this</a></p>` + "\n"},
		{"[@Alice](user:42)", "<p><a>@Alice</a></p>\n"},
		{"[x](file:1) ![y](file:1)", "<p><a>x</a> y</p>\n"},
		{"![pic *one*](/p.png)", `<p><img src="/p.png" alt="pic one" /></p>` + "\n"},
		{"[x](javascript:alert(1))", "<p><a>x</a></p>\n"},
	} {
		if got := r.HTML(Parse(c.md)); got != c.html {
			t.Errorf("%q: got %q, want %q", c.md, got, c.html)
		}
	}
}
