package opc

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"path"
	"strings"
)

const typesNamespace = "http://schemas.openxmlformats.org/package/2006/content-types"

// declaration is the XML declaration Office writes on every part.
const declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n"

// contentTypes is [Content_Types].xml, in its original order so that a
// rewrite changes no more than it must.
type contentTypes struct {
	XMLName   xml.Name   `xml:"Types"`
	Defaults  []typeRule `xml:"Default"`
	Overrides []typeRule `xml:"Override"`
}

type typeRule struct {
	Extension   string `xml:"Extension,attr,omitempty"`
	PartName    string `xml:"PartName,attr,omitempty"`
	ContentType string `xml:"ContentType,attr"`
}

func parseContentTypes(data []byte) (*contentTypes, error) {
	var t contentTypes
	if err := xml.Unmarshal(data, &t); err != nil {
		return nil, fmt.Errorf("%w: %s: %v", ErrInvalid, contentTypesName, err)
	}
	if t.XMLName.Space != typesNamespace {
		return nil, fmt.Errorf("%w: %s: namespace %q", ErrInvalid, contentTypesName, t.XMLName.Space)
	}
	return &t, nil
}

// lookup applies the rules: an override for the part, else the default of its
// extension.
func (t *contentTypes) lookup(name string) string {
	for _, o := range t.Overrides {
		if strings.EqualFold(o.PartName, "/"+name) {
			return o.ContentType
		}
	}
	ext := strings.TrimPrefix(path.Ext(name), ".")
	for _, d := range t.Defaults {
		if strings.EqualFold(d.Extension, ext) {
			return d.ContentType
		}
	}
	return ""
}

func (t *contentTypes) override(name, contentType string) {
	for i, o := range t.Overrides {
		if strings.EqualFold(o.PartName, "/"+name) {
			t.Overrides[i].ContentType = contentType
			return
		}
	}
	t.Overrides = append(t.Overrides, typeRule{PartName: "/" + name, ContentType: contentType})
}

func (t *contentTypes) removeOverride(name string) bool {
	for i, o := range t.Overrides {
		if strings.EqualFold(o.PartName, "/"+name) {
			t.Overrides = append(t.Overrides[:i], t.Overrides[i+1:]...)
			return true
		}
	}
	return false
}

func (t *contentTypes) marshal() []byte {
	var buf bytes.Buffer
	buf.WriteString(declaration)
	buf.WriteString(`<Types xmlns="` + typesNamespace + `">`)
	for _, d := range t.Defaults {
		fmt.Fprintf(&buf, `<Default Extension="%s" ContentType="%s"/>`, escape(d.Extension), escape(d.ContentType))
	}
	for _, o := range t.Overrides {
		fmt.Fprintf(&buf, `<Override PartName="%s" ContentType="%s"/>`, escape(o.PartName), escape(o.ContentType))
	}
	buf.WriteString(`</Types>`)
	return buf.Bytes()
}

func escape(s string) string {
	var b strings.Builder
	xml.EscapeText(&b, []byte(s))
	return b.String()
}
