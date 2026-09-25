package pagination

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
)

// Font holds the metrics layout needs from a TrueType font, in em.
type Font struct {
	advance  map[rune]float64
	notdef   float64
	ascent   float64
	descent  float64
	external float64
}

var errFont = errors.New("unsupported font")

func LoadFont(path string) (*Font, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	f, err := parseFont(data)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return f, nil
}

func parseFont(data []byte) (*Font, error) {
	tables := map[string][]byte{}
	if len(data) < 12 {
		return nil, errFont
	}
	n := int(binary.BigEndian.Uint16(data[4:]))
	for i := range n {
		rec := data[12+16*i:]
		off, size := binary.BigEndian.Uint32(rec[8:]), binary.BigEndian.Uint32(rec[12:])
		if uint64(off)+uint64(size) > uint64(len(data)) {
			return nil, errFont
		}
		tables[string(rec[:4])] = data[off : off+size]
	}
	head, hhea, os2, hmtx, cmap := tables["head"], tables["hhea"], tables["OS/2"], tables["hmtx"], tables["cmap"]
	if len(head) < 54 || len(hhea) < 36 || len(os2) < 78 || hmtx == nil || cmap == nil {
		return nil, errFont
	}
	em := float64(binary.BigEndian.Uint16(head[18:]))
	u16 := func(b []byte, at int) float64 { return float64(binary.BigEndian.Uint16(b[at:])) }
	i16 := func(b []byte, at int) float64 { return float64(int16(binary.BigEndian.Uint16(b[at:]))) }

	// The metrics of GDI, which Word lays out with: the Windows ascent and
	// descent, plus whatever line gap they do not already cover.
	winAscent, winDescent := u16(os2, 74), u16(os2, 76)
	hheaHeight := i16(hhea, 4) - i16(hhea, 6)
	external := max(0, i16(hhea, 8)-(winAscent+winDescent-hheaHeight))

	metrics := int(binary.BigEndian.Uint16(hhea[34:]))
	if metrics == 0 || len(hmtx) < 4*metrics {
		return nil, errFont
	}
	advance := func(glyph int) float64 {
		glyph = min(glyph, metrics-1)
		return u16(hmtx, 4*glyph) / em
	}
	glyphs, err := parseCmap(cmap)
	if err != nil {
		return nil, err
	}
	f := &Font{
		advance:  make(map[rune]float64, len(glyphs)),
		notdef:   advance(0),
		ascent:   winAscent / em,
		descent:  winDescent / em,
		external: external / em,
	}
	for r, g := range glyphs {
		f.advance[r] = advance(g)
	}
	return f, nil
}

// parseCmap reads the Unicode character map, format 12 or 4.
func parseCmap(cmap []byte) (map[rune]int, error) {
	if len(cmap) < 4 {
		return nil, errFont
	}
	var best []byte
	bestRank := 0
	for i := range int(binary.BigEndian.Uint16(cmap[2:])) {
		rec := cmap[4+8*i:]
		platform, encoding := binary.BigEndian.Uint16(rec), binary.BigEndian.Uint16(rec[2:])
		off := binary.BigEndian.Uint32(rec[4:])
		if int(off)+4 > len(cmap) {
			continue
		}
		sub := cmap[off:]
		rank := 0
		switch format := binary.BigEndian.Uint16(sub); {
		case format == 12 && (platform == 3 && encoding == 10 || platform == 0):
			rank = 2
		case format == 4 && (platform == 3 && encoding == 1 || platform == 0):
			rank = 1
		}
		if rank > bestRank {
			best, bestRank = sub, rank
		}
	}
	glyphs := map[rune]int{}
	switch bestRank {
	case 2:
		groups := int(binary.BigEndian.Uint32(best[12:]))
		for i := range groups {
			g := best[16+12*i:]
			start, end, glyph := binary.BigEndian.Uint32(g), binary.BigEndian.Uint32(g[4:]), binary.BigEndian.Uint32(g[8:])
			for c := start; c <= end && c < 0x110000; c++ {
				glyphs[rune(c)] = int(glyph + c - start)
			}
		}
	case 1:
		segs := int(binary.BigEndian.Uint16(best[6:])) / 2
		ends, starts, deltas, offsets := 14, 16+2*segs, 16+4*segs, 16+6*segs
		for i := range segs {
			end := int(binary.BigEndian.Uint16(best[ends+2*i:]))
			start := int(binary.BigEndian.Uint16(best[starts+2*i:]))
			delta := int(binary.BigEndian.Uint16(best[deltas+2*i:]))
			rangeOff := int(binary.BigEndian.Uint16(best[offsets+2*i:]))
			for c := start; c <= end && c != 0xFFFF; c++ {
				g := 0
				if rangeOff == 0 {
					g = (c + delta) & 0xFFFF
				} else {
					at := offsets + 2*i + rangeOff + 2*(c-start)
					if at+2 > len(best) {
						continue
					}
					if g = int(binary.BigEndian.Uint16(best[at:])); g != 0 {
						g = (g + delta) & 0xFFFF
					}
				}
				if g != 0 {
					glyphs[rune(c)] = g
				}
			}
		}
	default:
		return nil, errFont
	}
	return glyphs, nil
}

// Advance is the width of r in em; a character the font lacks gets the
// width of its missing glyph.
func (f *Font) Advance(r rune) float64 {
	if a, ok := f.advance[r]; ok {
		return a
	}
	return f.notdef
}

func (f *Font) Has(r rune) bool {
	_, ok := f.advance[r]
	return ok
}

// LineHeight is the height of a single-spaced line, in em.
func (f *Font) LineHeight() float64 {
	return f.ascent + f.descent + f.external
}
