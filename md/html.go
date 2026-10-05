package md

import (
	"strconv"
	"strings"
)

// HTML renders a document, its links leading where they are written.
func HTML(doc *Node) string {
	return Renderer{}.HTML(doc)
}

// Renderer renders documents in HTML. Raw HTML is shown as text, as the
// editor shows it, and links that could run code lead nowhere.
type Renderer struct {
	// URL is where a link or a picture leads, "" for nowhere: the host
	// knows what [[Note]], user:42 or the pictures it keeps stand for. Nil
	// keeps destinations as written.
	URL func(link *Node) string
}

func (r Renderer) HTML(doc *Node) string {
	w := htmlWriter{url: r.URL}
	w.node(doc, false)
	return w.b.String()
}

type htmlWriter struct {
	b   strings.Builder
	url func(*Node) string
	// raw lets raw HTML through, as CommonMark renders it.
	raw bool
}

// href is where a link or a picture leads, "" for nowhere.
func (w *htmlWriter) href(n *Node) string {
	dest := n.Dest
	if w.url != nil {
		dest = w.url(n)
	}
	if dest == "" || !w.raw && !safeURL(dest) {
		return ""
	}
	return normalizeURL(dest)
}

func (w *htmlWriter) cr() {
	if s := w.b.String(); s != "" && s[len(s)-1] != '\n' {
		w.b.WriteByte('\n')
	}
}

func (w *htmlWriter) out(s string) { w.b.WriteString(escapeHTML(s)) }

func (w *htmlWriter) children(n *Node) {
	for _, c := range n.Children {
		w.node(c, false)
	}
}

// node renders a node; tight tells the children of an item of a tight list,
// whose paragraphs have no tags.
func (w *htmlWriter) node(n *Node, tight bool) {
	switch n.Kind {
	case Document, Definition, FrontMatter:
		if n.Kind == Document {
			w.children(n)
		}
	case Paragraph:
		if tight {
			w.children(n)
			return
		}
		w.cr()
		w.b.WriteString("<p>")
		w.children(n)
		w.b.WriteString("</p>")
		w.cr()
	case Heading:
		w.cr()
		tag := "h" + strconv.Itoa(n.Level)
		w.b.WriteString("<" + tag + ">")
		w.children(n)
		w.b.WriteString("</" + tag + ">")
		w.cr()
	case ThematicBreak:
		w.cr()
		w.b.WriteString("<hr />")
		w.cr()
	case CodeBlock:
		w.cr()
		w.b.WriteString("<pre><code")
		if words := strings.Fields(n.Info); len(words) > 0 {
			lang := words[0]
			if !strings.HasPrefix(lang, "language-") {
				lang = "language-" + lang
			}
			w.b.WriteString(` class="` + escapeHTML(lang) + `"`)
		}
		w.b.WriteString(">")
		w.out(n.Literal)
		w.b.WriteString("</code></pre>")
		w.cr()
	case HTMLBlock:
		w.cr()
		if w.raw {
			w.b.WriteString(n.Literal)
		} else {
			w.b.WriteString("<p>")
			w.out(n.Literal)
			w.b.WriteString("</p>")
		}
		w.cr()
	case MathBlock:
		w.cr()
		w.b.WriteString(`<div class="math">`)
		w.out(n.Literal)
		w.b.WriteString("</div>")
		w.cr()
	case Quote:
		w.cr()
		w.b.WriteString("<blockquote>")
		w.cr()
		w.children(n)
		w.cr()
		w.b.WriteString("</blockquote>")
		w.cr()
	case List:
		tag := "ul"
		if n.Ordered {
			tag = "ol"
		}
		w.cr()
		w.b.WriteString("<" + tag)
		if n.Ordered && n.Number != 1 {
			w.b.WriteString(` start="` + strconv.Itoa(n.Number) + `"`)
		}
		w.b.WriteString(">")
		w.cr()
		for _, c := range n.Children {
			w.node(c, n.Tight)
		}
		w.cr()
		w.b.WriteString("</" + tag + ">")
		w.cr()
	case Item:
		w.b.WriteString("<li>")
		switch n.Task {
		case TaskOpen:
			w.b.WriteString(`<input disabled="" type="checkbox"> `)
		case TaskDone:
			w.b.WriteString(`<input checked="" disabled="" type="checkbox"> `)
		}
		for _, c := range n.Children {
			w.node(c, tight)
		}
		w.b.WriteString("</li>")
		w.cr()
	case Table:
		w.cr()
		w.b.WriteString("<table>")
		body := false
		for _, row := range n.Children {
			w.cr()
			if row.Header {
				w.b.WriteString("<thead>")
				w.cr()
			} else if !body {
				w.b.WriteString("<tbody>")
				w.cr()
				body = true
			}
			w.b.WriteString("<tr>")
			for i, cell := range row.Children {
				w.cr()
				tag := "td"
				if row.Header {
					tag = "th"
				}
				w.b.WriteString("<" + tag)
				switch n.Align[i] {
				case AlignLeft:
					w.b.WriteString(` align="left"`)
				case AlignCenter:
					w.b.WriteString(` align="center"`)
				case AlignRight:
					w.b.WriteString(` align="right"`)
				}
				w.b.WriteString(">")
				w.children(cell)
				w.b.WriteString("</" + tag + ">")
			}
			w.cr()
			w.b.WriteString("</tr>")
			if row.Header {
				w.cr()
				w.b.WriteString("</thead>")
			}
		}
		if body {
			w.cr()
			w.b.WriteString("</tbody>")
			w.cr()
		}
		w.cr()
		w.b.WriteString("</table>")
		w.cr()
	case Text, Escape, Entity:
		w.out(n.Literal)
	case SoftBreak:
		w.b.WriteString("\n")
	case HardBreak:
		w.b.WriteString("<br />\n")
	case Code:
		w.b.WriteString("<code>")
		w.out(n.Literal)
		w.b.WriteString("</code>")
	case Emphasis, Strong, Strike, Highlight:
		tag := map[Kind]string{Emphasis: "em", Strong: "strong", Strike: "del", Highlight: "mark"}[n.Kind]
		w.b.WriteString("<" + tag + ">")
		w.children(n)
		w.b.WriteString("</" + tag + ">")
	case Link:
		w.b.WriteString("<a")
		if href := w.href(n); href != "" || w.raw {
			w.b.WriteString(` href="` + escapeHTML(href) + `"`)
		}
		if n.Title != "" {
			w.b.WriteString(` title="` + escapeHTML(n.Title) + `"`)
		}
		w.b.WriteString(">")
		w.children(n)
		w.b.WriteString("</a>")
	case Image:
		src := w.href(n)
		if src == "" && !w.raw {
			w.out(Plain(n))
			return
		}
		w.b.WriteString(`<img src="` + escapeHTML(src) + `" alt="` + escapeHTML(Plain(n)) + `"`)
		if n.Title != "" {
			w.b.WriteString(` title="` + escapeHTML(n.Title) + `"`)
		}
		w.b.WriteString(" />")
	case InlineHTML:
		if w.raw {
			w.b.WriteString(n.Literal)
		} else {
			w.out(n.Literal)
		}
	case Math:
		w.b.WriteString(`<span class="math">`)
		w.out(n.Literal)
		w.b.WriteString("</span>")
	}
}

// Plain is the text of a node without its syntax: what a link reads as,
// the description of a picture.
func Plain(n *Node) string {
	var b strings.Builder
	n.Walk(func(c *Node) bool {
		switch c.Kind {
		case Text, Escape, Entity, Code, Math:
			b.WriteString(c.Literal)
		case SoftBreak, HardBreak:
			b.WriteByte('\n')
		}
		return true
	})
	return b.String()
}

func escapeHTML(s string) string {
	if !strings.ContainsAny(s, `&<>"`) {
		return s
	}
	return htmlEscaper.Replace(s)
}

var htmlEscaper = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")

// safeURL tells the destinations a browser follows without running code.
func safeURL(url string) bool {
	scheme, _, ok := strings.Cut(url, ":")
	if !ok {
		return true
	}
	switch strings.ToLower(scheme) {
	case "javascript", "vbscript", "file":
		return false
	case "data":
		l := strings.ToLower(url)
		for _, t := range [...]string{"data:image/png", "data:image/gif", "data:image/jpeg", "data:image/webp"} {
			if strings.HasPrefix(l, t) {
				return true
			}
		}
		return false
	}
	return true
}

// normalizeURL percent-encodes what a URL may not hold, leaving its
// reserved characters and the escapes it already has.
func normalizeURL(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '%' && i+2 < len(s) && isHex(s[i+1]) && isHex(s[i+2]):
			b.WriteString(s[i : i+3])
			i += 2
		case isAlnum(c) || c < 0x80 && strings.IndexByte(";/?:@&=+$,-_.!~*'()#", c) >= 0:
			b.WriteByte(c)
		default:
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&15])
		}
	}
	return b.String()
}

func isHex(c byte) bool { return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F' }
