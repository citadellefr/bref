package opc

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// ooxmlExtensions are the files the corpus tests open.
var ooxmlExtensions = []string{
	".docx", ".docm", ".dotx", ".dotm",
	".xlsx", ".xlsm", ".xltx", ".xltm",
	".pptx", ".pptm", ".potx", ".potm", ".ppsx", ".ppsm",
}

// corpus lists the OOXML files fetched by corpus/fetch.sh.
func corpus(t *testing.T) []string {
	t.Helper()
	root := filepath.Join("..", "corpus", "files")
	if _, err := os.Stat(root); err != nil {
		t.Skip("no corpus: run corpus/fetch.sh")
	}
	var files []string
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() && slices.Contains(ooxmlExtensions, strings.ToLower(filepath.Ext(path))) {
			files = append(files, path)
		}
		return err
	})
	return files
}

// readRelationships reads and resolves every relationship of the package.
func readRelationships(p *Package) error {
	for _, name := range append([]string{""}, p.Names()...) {
		rels, err := p.Relationships(name)
		if err != nil {
			return err
		}
		for _, r := range rels {
			if _, err := Resolve(name, r.Target); !r.External && err != nil {
				return err
			}
		}
	}
	return nil
}

func TestCorpusRoundTrip(t *testing.T) {
	var opened, rejected int
	for _, path := range corpus(t) {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		p, err := Open(data, Limits{})
		if err != nil {
			rejected++
			t.Logf("rejected %s: %v", filepath.Base(path), err)
			continue
		}
		if err := readRelationships(p); err != nil {
			rejected++
			t.Logf("rejected %s: %v", filepath.Base(path), err)
			continue
		}
		opened++
		out, err := p.Bytes()
		if err != nil {
			t.Errorf("%s: %v", path, err)
			continue
		}
		q, err := Open(out, Limits{})
		if err != nil {
			t.Errorf("%s: written package does not open: %v", path, err)
			continue
		}
		if !slices.Equal(p.Names(), q.Names()) {
			t.Errorf("%s: parts changed", path)
			continue
		}
		if !slices.EqualFunc(rawEntries(t, data), rawEntries(t, out), bytes.Equal) {
			t.Errorf("%s: compressed data changed", path)
		}
	}
	t.Logf("%d packages kept intact, %d rejected", opened, rejected)
}
