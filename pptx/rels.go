package pptx

import (
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"hash/crc32"
	"path"
	"strconv"
	"strings"

	"github.com/citadellefr/bref/internal/xmldom"
	"github.com/citadellefr/bref/opc"
)

// A relationship an element of the document points to, by the name the
// document gives it: "@" and a hash, which does not depend on the part the
// element is in. An element can so move from a slide to another, and its
// pictures and links follow; the name of a picture stands for its content,
// which the host serves it by.
type rel struct {
	typ      string
	target   string // a part name, or a URL when external
	external bool
}

const (
	relSlide       = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
	relSlideLayout = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
	relSlideMaster = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster"
	relTheme       = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme"
	relNotesSlide  = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide"
	relImage       = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
	relHyperlink   = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink"
)

// partRels are the relationships of a part, as read.
type partRels struct {
	list []opc.Relationship
	byID map[string]opc.Relationship
}

func (d *Document) readRels(part string) (*partRels, error) {
	list, err := d.pkg.Relationships(part)
	if err != nil {
		return nil, err
	}
	r := &partRels{list: list, byID: map[string]opc.Relationship{}}
	for _, x := range list {
		r.byID[x.ID] = x
	}
	return r, nil
}

// target is the part a relationship of source points to, "" when it points
// outside the package or nowhere.
func (r *partRels) target(source, id string) string {
	x, ok := r.byID[id]
	if !ok || x.External {
		return ""
	}
	name, err := opc.Resolve(source, x.Target)
	if err != nil {
		return ""
	}
	return name
}

// ofType is the first relationship of that type.
func (r *partRels) ofType(source, typ string) string {
	for _, x := range r.list {
		if x.Type == typ && !x.External {
			if name, err := opc.Resolve(source, x.Target); err == nil {
				return name
			}
		}
	}
	return ""
}

// name gives the relationship id of source its document-wide name, "" when
// there is no such relationship.
func (d *Document) name(source string, rels *partRels, id string) string {
	x, ok := rels.byID[id]
	if !ok {
		return ""
	}
	r := rel{typ: x.Type, target: x.Target, external: x.External}
	if !x.External {
		name, err := opc.Resolve(source, x.Target)
		if err != nil {
			return ""
		}
		r.target = name
	}
	n, ok := d.names[r]
	if !ok {
		n = nameOf(d.pkg, r)
		d.names[r] = n
	}
	if n != "" {
		if _, known := d.rels[n]; !known {
			d.rels[n] = r
		}
	}
	return n
}

// nameOf is the name of a relationship: made of the checksum and size of
// the content of a picture, of its type and target otherwise.
func nameOf(pkg *opc.Package, r rel) string {
	var sum [32]byte
	if r.typ == relImage && !r.external {
		crc, size, ok := pkg.Checksum(r.target)
		if !ok {
			data, err := pkg.Read(r.target)
			if err != nil {
				return ""
			}
			crc, size = crc32.ChecksumIEEE(data), uint64(len(data))
		}
		sum = sha256.Sum256(binary.BigEndian.AppendUint64(binary.BigEndian.AppendUint32(nil, crc), size))
	} else {
		sum = sha256.Sum256([]byte(r.typ + "\x00" + r.target + "\x00" + strconv.FormatBool(r.external)))
	}
	return "@" + base62(sum[:])
}

func base62(b []byte) string {
	const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	v := binary.BigEndian.Uint64(b)
	out := make([]byte, 11)
	for i := range out {
		out[i] = digits[v%62]
		v /= 62
	}
	return string(out)
}

// nameRels replaces, in e and its descendants, the relationship ids of
// source by their names.
func (d *Document) nameRels(e *xmldom.Element, source string, rels *partRels, spaces map[string]string) {
	walkRels(e, spaces, func(el *xmldom.Element, attr, value string) {
		if n := d.name(source, rels, value); n != "" {
			el.Set(attr, n)
		}
	})
}

// walkRels calls f for every attribute in the relationships namespace of e
// and its descendants, prefixes resolved from spaces and the declarations
// met on the way.
func walkRels(e *xmldom.Element, spaces map[string]string, f func(e *xmldom.Element, attr, value string)) {
	local := spaces
	for _, a := range e.Attrs {
		if a.Name == "xmlns" || strings.HasPrefix(a.Name, "xmlns:") {
			local = e.Spaces()
			for k, v := range spaces {
				if _, set := local[k]; !set {
					local[k] = v
				}
			}
			break
		}
	}
	for _, a := range e.Attrs {
		prefix, _, found := strings.Cut(a.Name, ":")
		if found && local[prefix] == relNS {
			f(e, a.Name, a.Value)
		}
	}
	for _, c := range e.Elements() {
		walkRels(c, local, f)
	}
}

// relsWriter gives the relationships of a part being written their ids,
// keeping those it had.
type relsWriter struct {
	names   func(name string) (rel, bool)
	source  string
	list    []opc.Relationship
	changed bool
}

// id is the relationship id of a name, added to the part when it had none;
// "" when the name is unknown.
func (w *relsWriter) id(name string) string {
	r, ok := w.names(name)
	if !ok {
		return ""
	}
	return w.ensure(r)
}

// ensure is the id of a relationship to r, added if the part has none.
func (w *relsWriter) ensure(r rel) string {
	for _, x := range w.list {
		if x.Type == r.typ && x.External == r.external && w.same(x, r) {
			return x.ID
		}
	}
	target := r.target
	if !r.external {
		target = relative(w.source, r.target)
	}
	id := w.free()
	w.list = append(w.list, opc.Relationship{ID: id, Type: r.typ, Target: target, External: r.external})
	w.changed = true
	return id
}

// drop removes the relationships of a type whose target is not keep.
func (w *relsWriter) drop(typ string, keep rel) {
	out := w.list[:0]
	for _, x := range w.list {
		if x.Type == typ && !w.same(x, keep) {
			w.changed = true
			continue
		}
		out = append(out, x)
	}
	w.list = out
}

func (w *relsWriter) same(x opc.Relationship, r rel) bool {
	if r.external {
		return x.Target == r.target
	}
	name, err := opc.Resolve(w.source, x.Target)
	return err == nil && name == r.target
}

func (w *relsWriter) free() string {
	used := map[string]bool{}
	for _, x := range w.list {
		used[x.ID] = true
	}
	for n := len(w.list) + 1; ; n++ {
		if id := fmt.Sprintf("rId%d", n); !used[id] {
			return id
		}
	}
}

// resolve replaces the names in e by relationship ids of the part, and
// drops the attributes whose name it does not know.
func (w *relsWriter) resolve(e *xmldom.Element, spaces map[string]string) {
	walkRels(e, spaces, func(el *xmldom.Element, attr, value string) {
		if !strings.HasPrefix(value, "@") {
			return
		}
		if id := w.id(value); id != "" {
			el.Set(attr, id)
		} else {
			el.Unset(attr)
		}
	})
}

// relative is the target of a relationship from source to the part name.
func relative(source, name string) string {
	from := strings.Split(path.Dir(source), "/")
	to := strings.Split(name, "/")
	if path.Dir(source) == "." {
		from = nil
	}
	i := 0
	for i < len(from) && i < len(to)-1 && from[i] == to[i] {
		i++
	}
	return strings.Repeat("../", len(from)-i) + strings.Join(to[i:], "/")
}

// marshalRels writes a relationships part.
func marshalRels(list []opc.Relationship) []byte {
	root := xmldom.New("", "Relationships", "xmlns", "http://schemas.openxmlformats.org/package/2006/relationships")
	for _, x := range list {
		r := xmldom.New("", "Relationship", "Id", x.ID, "Type", x.Type, "Target", x.Target)
		if x.External {
			r.Set("TargetMode", "External")
		}
		root.Append(r)
	}
	return append([]byte("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"), root.Bytes()...)
}
