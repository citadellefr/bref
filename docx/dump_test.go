package docx

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/citadellefr/bref/internal/partrel"
)

// TestDump writes the trees and pictures of documents to $BREF_DUMP, for
// the Dart package to draw them: $BREF_DUMP_FILES lists them, relative to
// corpus/files.
func TestDump(t *testing.T) {
	dir := os.Getenv("BREF_DUMP")
	if dir == "" {
		t.Skip("BREF_DUMP not set")
	}
	for _, name := range strings.Split(os.Getenv("BREF_DUMP_FILES"), ",") {
		data, err := os.ReadFile(filepath.Join("../corpus/files", name))
		if err != nil {
			t.Fatal(err)
		}
		d, tree, err := Open(data)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		base := filepath.Join(dir, strings.TrimSuffix(filepath.Base(name), filepath.Ext(name)))
		nodes, _ := json.Marshal(tree.Edit())
		if err := os.WriteFile(base+".json", nodes, 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.MkdirAll(base, 0o755); err != nil {
			t.Fatal(err)
		}
		for n, r := range d.names.All() {
			if r.Type != partrel.Image || r.External {
				continue
			}
			picture, _, err := d.Media(strings.TrimPrefix(n, "@"))
			if err == nil {
				_ = os.WriteFile(filepath.Join(base, strings.TrimPrefix(n, "@")), picture, 0o644)
			}
		}
	}
}
