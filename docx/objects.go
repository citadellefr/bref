package docx

import (
	"encoding/json"
	"regexp"
	"strconv"
	"strings"

	"github.com/citadellefr/bref/internal/xmldom"
	"github.com/citadellefr/bref/ot"
)

const (
	wpNS  = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
	aNS   = "http://schemas.openxmlformats.org/drawingml/2006/main"
	vmlNS = "urn:schemas-microsoft-com:vml"
)

// Picture is what the editor needs of a drawing or VML shape: its size in
// EMU, its picture, and where it floats when it is not in the line.
type Picture struct {
	Media string `json:"media,omitempty"`
	W     int64  `json:"w"`
	H     int64  `json:"h"`
	// Crop is the part of the picture cut off each side, in 1000ths of a
	// percent: "l", "t", "r", "b".
	Crop  map[string]int `json:"crop,omitempty"`
	Float *Float         `json:"float,omitempty"`
	Descr string         `json:"descr,omitempty"`
}

// Float is the position of an anchored drawing.
type Float struct {
	RelX   string `json:"relX,omitempty"`
	X      int64  `json:"x"`
	AlignX string `json:"alignX,omitempty"`
	RelY   string `json:"relY,omitempty"`
	Y      int64  `json:"y"`
	AlignY string `json:"alignY,omitempty"`
	// Wrap is how text flows around: "square" "tight" "through"
	// "topAndBottom" "none".
	Wrap   string `json:"wrap"`
	Behind bool   `json:"behind,omitempty"`
}

// describe adds to the attributes of an Object what it means, in keys a
// client reads:
//
//	img     a Picture, as JSON
//	fld     a field character: "begin" "separate" "end"
//	instr   the instructions of a field
//	br      a break: "page" "column", or "textWrapping" with clear
//	sym     a symbol: "font:F020"
//	note    a note reference: "footnote:2" "endnote:1", "ref" for the number in a note
//	comment the id of a comment referred to
//	bm      the name of a bookmark starting
//	math    "1", an equation
func describe(e *xmldom.Element, attrs ot.Attrs) {
	switch e.Space {
	case NS:
	case mcNS:
		if e.Local == "AlternateContent" {
			if c := e.Child(mcNS, "Choice"); c != nil {
				for _, inner := range c.Elements() {
					describe(inner, attrs)
				}
			}
		}
		return
	case "http://schemas.openxmlformats.org/officeDocument/2006/math":
		attrs["math"] = "1"
		return
	default:
		return
	}
	switch e.Local {
	case "drawing":
		if p := drawing(e); p != nil {
			data, _ := json.Marshal(p)
			attrs["img"] = string(data)
		}
	case "pict", "object":
		if p := vml(e); p != nil {
			data, _ := json.Marshal(p)
			attrs["img"] = string(data)
		}
	case "fldChar":
		attrs["fld"] = attr(e, "fldCharType")
	case "instrText", "delInstrText":
		attrs["instr"] = e.Text()
	case "br":
		kind := attr(e, "type")
		if kind == "" {
			kind = "textWrapping"
		}
		attrs["br"] = kind
	case "sym":
		attrs["sym"] = attr(e, "font") + ":" + attr(e, "char")
	case "footnoteReference", "endnoteReference":
		attrs["note"] = strings.TrimSuffix(e.Local, "Reference") + ":" + attr(e, "id")
	case "footnoteRef", "endnoteRef":
		attrs["note"] = "ref"
	case "commentReference":
		attrs["comment"] = attr(e, "id")
	case "bookmarkStart":
		attrs["bm"] = attr(e, "name")
	}
}

// drawing reads a w:drawing.
func drawing(e *xmldom.Element) *Picture {
	for _, c := range e.Elements() {
		if c.Space != wpNS || c.Local != "inline" && c.Local != "anchor" {
			continue
		}
		p := &Picture{}
		if ext := c.Child(wpNS, "extent"); ext != nil {
			p.W, _ = strconv.ParseInt(ext.Get("cx"), 10, 64)
			p.H, _ = strconv.ParseInt(ext.Get("cy"), 10, 64)
		}
		if doc := c.Child(wpNS, "docPr"); doc != nil {
			p.Descr = doc.Get("descr")
		}
		if blip := find(c, aNS, "blip"); blip != nil {
			p.Media = strings.TrimPrefix(blip.Get("r:embed"), "@")
			if src := find(c, aNS, "srcRect"); src != nil {
				p.Crop = map[string]int{}
				for _, side := range []string{"l", "t", "r", "b"} {
					if n, err := strconv.Atoi(src.Get(side)); err == nil && n != 0 {
						p.Crop[side] = n
					}
				}
				if len(p.Crop) == 0 {
					p.Crop = nil
				}
			}
		}
		if c.Local == "anchor" {
			p.Float = anchor(c)
		}
		return p
	}
	return nil
}

func anchor(a *xmldom.Element) *Float {
	f := &Float{Wrap: "none", Behind: truthy(a.Get("behindDoc"))}
	for _, axis := range []struct {
		local      string
		rel, align *string
		offset     *int64
	}{{"positionH", &f.RelX, &f.AlignX, &f.X}, {"positionV", &f.RelY, &f.AlignY, &f.Y}} {
		pos := a.Child(wpNS, axis.local)
		if pos == nil {
			continue
		}
		*axis.rel = pos.Get("relativeFrom")
		if al := pos.Child(wpNS, "align"); al != nil {
			*axis.align = strings.TrimSpace(al.Text())
		}
		if off := pos.Child(wpNS, "posOffset"); off != nil {
			*axis.offset, _ = strconv.ParseInt(strings.TrimSpace(off.Text()), 10, 64)
		}
	}
	for _, c := range a.Elements() {
		if c.Space == wpNS && strings.HasPrefix(c.Local, "wrap") {
			f.Wrap = strings.TrimPrefix(c.Local, "wrap")
			f.Wrap = strings.ToLower(f.Wrap[:1]) + f.Wrap[1:]
		}
	}
	return f
}

// find is the first descendant of e with that name.
func find(e *xmldom.Element, space, local string) *xmldom.Element {
	for _, c := range e.Elements() {
		if c.Space == space && c.Local == local {
			return c
		}
		if f := find(c, space, local); f != nil {
			return f
		}
	}
	return nil
}

var vmlDimension = regexp.MustCompile(`(width|height):\s*([\d.]+)(pt|in|px|cm|mm)?`)

// vml reads an inline VML shape: its size and picture.
func vml(e *xmldom.Element) *Picture {
	var shape *xmldom.Element
	for _, local := range []string{"shape", "rect", "group", "roundrect", "oval"} {
		if shape = find(e, vmlNS, local); shape != nil {
			break
		}
	}
	if shape == nil {
		return nil
	}
	style := shape.Get("style")
	if strings.Contains(style, "position:absolute") {
		return nil
	}
	p := &Picture{}
	for _, m := range vmlDimension.FindAllStringSubmatch(style, -1) {
		v, _ := strconv.ParseFloat(m[2], 64)
		switch m[3] {
		case "in":
			v *= 72
		case "px":
			v *= 0.75
		case "cm":
			v *= 72 / 2.54
		case "mm":
			v *= 72 / 25.4
		}
		if m[1] == "width" {
			p.W = int64(v * 12700)
		} else {
			p.H = int64(v * 12700)
		}
	}
	if img := find(shape, vmlNS, "imagedata"); img != nil {
		p.Media = strings.TrimPrefix(img.Get("r:id"), "@")
	}
	if p.W == 0 || p.H == 0 {
		return nil
	}
	return p
}
