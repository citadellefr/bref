package pagination

import (
	"os"
	"path/filepath"
	"strings"
)

// twins are the free fonts drawn on the metrics of Office fonts: same
// advance widths, same line heights, hence the same line breaks.
var twins = map[string]string{
	"calibri":          "Carlito",
	"cambria":          "Caladea",
	"arial":            "LiberationSans",
	"helvetica":        "LiberationSans",
	"times new roman":  "LiberationSerif",
	"times":            "LiberationSerif",
	"courier new":      "LiberationMono",
	"courier":          "LiberationMono",
	"carlito":          "Carlito",
	"caladea":          "Caladea",
	"liberation sans":  "LiberationSans",
	"liberation serif": "LiberationSerif",
	"liberation mono":  "LiberationMono",
}

// symbolFonts draw bullets and signs, whose widths barely move a line break.
var symbolFonts = map[string]bool{"symbol": true, "wingdings": true, "wingdings 2": true, "wingdings 3": true, "webdings": true}

// FontSet finds the twin of an Office font among font files.
type FontSet struct {
	files map[string]string // "Carlito-BoldItalic" → path
	cache map[string]*Font
}

// NewFontSet indexes the .ttf files under the directories.
func NewFontSet(dirs ...string) *FontSet {
	fs := &FontSet{files: map[string]string{}, cache: map[string]*Font{}}
	for _, dir := range dirs {
		filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
			if err == nil && strings.EqualFold(filepath.Ext(path), ".ttf") {
				fs.files[strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))] = path
			}
			return nil
		})
	}
	return fs
}

// Get is the twin of the named font, false with a stand-in when there is
// none: the lines then break where Word's may not.
func (fs *FontSet) Get(name string, bold, italic bool) (*Font, bool) {
	lower := strings.ToLower(strings.TrimSpace(name))
	family, ok := twins[lower]
	if !ok {
		family, ok = "LiberationSans", symbolFonts[lower]
	}
	style := "Regular"
	switch {
	case bold && italic:
		style = "BoldItalic"
	case bold:
		style = "Bold"
	case italic:
		style = "Italic"
	}
	key := family + "-" + style
	if f, found := fs.cache[key]; found {
		return f, ok && f != nil
	}
	f, err := LoadFont(fs.files[key])
	if err != nil {
		f = nil
	}
	fs.cache[key] = f
	return f, ok && f != nil
}

// Complete reports whether every twin is there.
func (fs *FontSet) Complete() bool {
	for _, family := range twins {
		if fs.files[family+"-Regular"] == "" {
			return false
		}
	}
	return true
}
