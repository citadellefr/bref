package docx

import (
	"errors"

	"github.com/citadellefr/bref/internal/partrel"
	"github.com/citadellefr/bref/ot"
)

var (
	ErrReadOnly = errors.New("docx: this part of the document cannot be edited")
	ErrNoMedia  = errors.New("docx: no such picture")
)

// holders are the nodes blocks go in.
var holders = map[string]bool{"body": true, "tc": true, "sdt": true, "hdr": true, "ftr": true, "note": true}

var blockTypes = map[string]bool{"text": true, "tbl": true, "sdt": true, "other": true}

// editable are the attributes a change may set, by node type.
var editable = func() map[string]map[string]bool {
	out := map[string]map[string]bool{"doc": {"sect": true}}
	for typ, list := range map[string][]tprop{"tbl": tblProps, "tr": trProps, "tc": tcProps} {
		out[typ] = map[string]bool{}
		for _, p := range list {
			if p.write != nil {
				out[typ][p.key] = true
			}
		}
	}
	out["tbl"]["grid"] = true
	return out
}()

// Check tells whether an edit only changes what can be edited: the blocks
// of the body, headers and footers, the sections, not the styles.
func (d *Document) Check(tree *ot.Tree, e ot.Edit) error {
	created := map[string]string{}
	typeOf := func(id string) string {
		if t, ok := created[id]; ok {
			return t
		}
		if n := tree.Node(id); n != nil {
			return n.Type
		}
		return ""
	}
	for _, c := range e {
		switch c.Op {
		case ot.OpNew:
			parent := typeOf(c.Parent)
			ok := blockTypes[c.Type] && holders[parent] ||
				c.Type == "tr" && parent == "tbl" ||
				c.Type == "tc" && parent == "tr" ||
				c.Type == "other" && (parent == "tbl" || parent == "tr") ||
				(c.Type == "hdr" || c.Type == "ftr") && c.Parent == "doc"
			if !ok || (c.Type == "text") != (c.Text != nil) {
				return ErrReadOnly
			}
			created[c.ID] = c.Type
		case ot.OpDel:
			switch typeOf(c.ID) {
			case "doc", "body", "hdr", "ftr", "note":
				return ErrReadOnly
			}
		case ot.OpSet:
			t := typeOf(c.ID)
			if t == "" {
				continue
			}
			if c.Key != "" && !blockTypes[t] && t != "tr" && t != "tc" {
				return ErrReadOnly
			}
			for k := range c.Attrs {
				if !editable[t][k] {
					return ErrReadOnly
				}
			}
		case ot.OpTxt:
			if t := typeOf(c.ID); t != "" && t != "text" {
				return ErrReadOnly
			}
		default:
			return ErrReadOnly
		}
	}
	return nil
}

// Media is a picture of the document, by the name its drawings give it,
// and its content type.
func (d *Document) Media(name string) ([]byte, string, error) {
	r, ok := d.names.Lookup("@" + name)
	if !ok || r.Type != partrel.Image || r.External {
		return nil, "", ErrNoMedia
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if p := d.pending[r.Target]; p != nil {
		return p.data, p.contentType, nil
	}
	data, err := d.pkg.Read(r.Target)
	if err != nil {
		return nil, "", errors.Join(ErrNoMedia, err)
	}
	return data, d.pkg.ContentType(r.Target), nil
}
