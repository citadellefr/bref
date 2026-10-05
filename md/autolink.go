package md

import (
	"strings"
	"unicode/utf8"
)

// The addresses GitHub links without brackets: www.example.com,
// https://example.com and someone@example.com, outside of link texts.

func (ip *inlineParser) bareLink(p *inl) bool {
	if !ip.ext(extAutolinks) || ip.brackets != nil {
		return false
	}
	start := ip.pos
	data := ip.text[start:]
	end := 0
	dest := ""
	switch ip.text[start] {
	case 'w':
		if start > 0 && !wwwBoundary(ip.text[start-1]) || !strings.HasPrefix(data, "www.") {
			return false
		}
		if end = checkDomain(data, false); end == 0 {
			return false
		}
		end = autolinkDelim(data, linkExtent(data, end))
		dest = "http://" + data[:end]
	case 'h', 'H', 'f', 'F':
		if start > 0 && isAlpha(ip.text[start-1]) {
			return false
		}
		scheme := schemeLength(data)
		if scheme == 0 || !validHostChar(data[scheme:]) {
			return false
		}
		domain := checkDomain(data[scheme:], true)
		if domain == 0 {
			return false
		}
		end = autolinkDelim(data, linkExtent(data, scheme+domain))
		if end <= scheme-3 {
			return false
		}
		dest = data[:end]
	default:
		return false
	}
	if end == 0 {
		return false
	}
	s := ip.span(start, start+end)
	link := &inl{n: &Node{Kind: Link, Form: LinkBare, Span: s, Dest: dest, URL: s}}
	link.append(&inl{n: &Node{Kind: Text, Span: s, Literal: data[:end]}})
	p.append(link)
	ip.pos = start + end
	return true
}

// linkAt tells where a bare link may start, for runs of text to stop there.
func (ip *inlineParser) linkAt(i int) bool {
	if !ip.ext(extAutolinks) || ip.brackets != nil {
		return false
	}
	switch ip.text[i] {
	case 'w':
		return wwwBoundary(ip.text[i-1]) && strings.HasPrefix(ip.text[i:], "www.")
	case 'h', 'H', 'f', 'F':
		return !isAlpha(ip.text[i-1]) && schemeLength(ip.text[i:]) > 0
	}
	return false
}

func wwwBoundary(c byte) bool { return strings.IndexByte("*_~(", c) >= 0 || isWhitespace(c) }

func isAlpha(c byte) bool { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' }

func isAlnum(c byte) bool { return isAlpha(c) || c >= '0' && c <= '9' }

func schemeLength(s string) int {
	for _, scheme := range [...]string{"http://", "https://", "ftp://"} {
		if len(s) > len(scheme) && strings.EqualFold(s[:len(scheme)], scheme) {
			return len(scheme)
		}
	}
	return 0
}

func validHostChar(s string) bool {
	r, n := utf8.DecodeRuneInString(s)
	return n > 0 && r != utf8.RuneError && r != '\v' && !isUnicodeSpace(r) && !isPunct(r)
}

// linkExtent goes on from end up to a space or a "<".
func linkExtent(data string, end int) int {
	for end < len(data) && !isWhitespace(data[end]) && data[end] != '<' {
		end++
	}
	return end
}

// checkDomain is the length of the domain data starts with, 0 if it has no
// period while one is needed, or an underscore in its last two parts.
func checkDomain(data string, allowShort bool) int {
	periods, under1, under2 := 0, 0, 0
	i := 1
	for i < len(data)-1 {
		if data[i] == '\\' && i < len(data)-2 {
			i++
		}
		switch c := data[i]; {
		case c == '_':
			under2++
		case c == '.':
			under1, under2 = under2, 0
			periods++
		case c != '-' && !validHostChar(data[i:]):
			goto done
		}
		_, n := utf8.DecodeRuneInString(data[i:])
		i += n
	}
done:
	if (under1 > 0 || under2 > 0) && periods <= 10 {
		return 0
	}
	if allowShort || periods > 0 {
		return i
	}
	return 0
}

// autolinkDelim leaves out of a link the punctuation that ends a sentence,
// unbalanced closing parentheses and a trailing entity.
func autolinkDelim(data string, end int) int {
	opening, closing := 0, 0
	for i := 0; i < end; i++ {
		switch data[i] {
		case '<':
			end = i
		case '(':
			opening++
		case ')':
			closing++
		}
	}
	for end > 0 {
		switch data[end-1] {
		case ')':
			if closing <= opening {
				return end
			}
			closing--
			end--
		case '?', '!', '.', ',', ':', '*', '_', '~', '\'', '"':
			end--
		case ';':
			i := end - 2
			for i > 0 && isAlpha(data[i]) {
				i--
			}
			if i >= 0 && i < end-2 && data[i] == '&' {
				end = i
			} else {
				end--
			}
		default:
			return end
		}
	}
	return end
}

// splitEmails links the mail addresses in the texts outside of links.
func splitEmails(nodes []*Node) []*Node {
	var out []*Node
	for _, n := range nodes {
		switch n.Kind {
		case Link, Image:
			out = append(out, n)
		case Text:
			out = append(out, emailsIn(n)...)
		default:
			n.Children = splitEmails(n.Children)
			out = append(out, n)
		}
	}
	return out
}

func emailsIn(t *Node) []*Node {
	data := t.Literal
	var out []*Node
	start, offset := 0, 0
	for offset < len(data)-start {
		at := strings.IndexByte(data[start+offset:], '@')
		if at < 0 {
			break
		}
		maxRewind := at
		atPos := start + offset + maxRewind
	found:
		mailto, xmpp := true, false
		rewind := 0
	rewinding:
		for ; rewind < maxRewind; rewind++ {
			c := data[atPos-rewind-1]
			switch {
			case isAlnum(c) || strings.IndexByte(".+-_", c) >= 0:
			case c == ':' && validProtocol("mailto:", data, atPos, rewind, maxRewind):
				mailto = false
			case c == ':' && validProtocol("xmpp:", data, atPos, rewind, maxRewind):
				mailto, xmpp = false, true
			default:
				break rewinding
			}
		}
		if rewind == 0 {
			offset += maxRewind + 1
			continue
		}
		linkEnd, periods := 1, 0
		for ; atPos+linkEnd < len(data); linkEnd++ {
			c := data[atPos+linkEnd]
			switch {
			case isAlnum(c):
			case c == '@':
				offset += maxRewind + 1
				maxRewind = linkEnd - 1
				atPos = start + offset + maxRewind
				goto found
			case c == '.' && atPos+linkEnd+1 < len(data) && isAlnum(data[atPos+linkEnd+1]):
				periods++
			case c == '/' && xmpp:
			case c != '-' && c != '_':
				goto scanned
			}
		}
	scanned:
		if last := data[atPos+linkEnd-1]; linkEnd < 2 || periods == 0 || !isAlpha(last) && last != '.' {
			offset += maxRewind + linkEnd
			continue
		}
		if linkEnd = autolinkDelim(data[atPos:], linkEnd); linkEnd == 0 {
			offset += maxRewind + 1
			continue
		}
		from, to := atPos-rewind, atPos+linkEnd
		if from > start {
			out = append(out, &Node{Kind: Text, Span: Span{t.Start + start, t.Start + from}, Literal: data[start:from]})
		}
		s := Span{t.Start + from, t.Start + to}
		dest := data[from:to]
		if mailto {
			dest = "mailto:" + dest
		}
		out = append(out, &Node{Kind: Link, Form: LinkBare, Span: s, Dest: dest, URL: s, Children: []*Node{{Kind: Text, Span: s, Literal: data[from:to]}}})
		start, offset = to, 0
	}
	if start == 0 {
		return []*Node{t}
	}
	if start < len(data) {
		out = append(out, &Node{Kind: Text, Span: Span{t.Start + start, t.End}, Literal: data[start:]})
	}
	return out
}

func validProtocol(protocol, data string, atPos, rewind, maxRewind int) bool {
	n := len(protocol)
	if n > maxRewind-rewind {
		return false
	}
	from := atPos - rewind - n
	if data[from:atPos-rewind] != protocol {
		return false
	}
	return n == maxRewind-rewind || !isAlnum(data[from-1])
}
