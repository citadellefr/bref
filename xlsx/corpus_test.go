package xlsx

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/citadellefr/bref/opc"
)

func workbooks(t *testing.T) []string {
	if testing.Short() {
		t.Skip("the corpus is not read in -short mode")
	}
	files, _ := filepath.Glob("../corpus/files/*/*")
	if len(files) == 0 {
		t.Skip("no corpus: corpus/fetch.sh")
	}
	var out []string
	for _, f := range files {
		switch strings.ToLower(filepath.Ext(f)) {
		case ".xlsx", ".xlsm", ".xltx":
			out = append(out, f)
		}
	}
	return out
}

func TestCorpusOpen(t *testing.T) {
	var opened, refused, cells int
	var slowest time.Duration
	var slowestName string
	reasons := map[string]int{}
	for _, f := range workbooks(t) {
		data, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		start := time.Now()
		_, tree, err := Open(data)
		took := time.Since(start)
		if took > slowest {
			slowest, slowestName = took, f
		}
		if took > time.Second {
			t.Logf("%s: %v", f, took)
		}
		if err != nil {
			refused++
			reason := err.Error()
			if errors.Is(err, opc.ErrCompound) || errors.Is(err, opc.ErrInvalid) {
				reason = "package"
			}
			reasons[reason]++
			continue
		}
		opened++
		for _, n := range tree.Children("book") {
			if n.Grid != nil {
				cells += n.Grid.Len()
			}
		}
	}
	t.Logf("%d opened, %d cells; slowest %s in %v; %d refused: %v", opened, cells, slowestName, slowest, refused, reasons)
}
