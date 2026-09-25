package opc

import (
	"archive/zip"
	"bytes"
	"compress/flate"
	"errors"
	"hash/crc32"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const minimalTypes = `<?xml version="1.0"?><Types xmlns="` + typesNamespace + `">` +
	`<Default Extension="xml" ContentType="application/xml"/></Types>`

type entry struct{ name, data string }

func makeZip(t testing.TB, entries ...entry) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, e := range entries {
		w, err := zw.Create(e.name)
		if err != nil {
			t.Fatal(err)
		}
		w.Write([]byte(e.data))
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func fixtures(t testing.TB) map[string][]byte {
	t.Helper()
	paths, _ := filepath.Glob("testdata/*.*")
	files := map[string][]byte{}
	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		files[filepath.Base(p)] = data
	}
	if len(files) == 0 {
		t.Fatal("no fixture")
	}
	return files
}

// rawEntries is the compressed data of every file entry, in archive order.
func rawEntries(t *testing.T, data []byte) [][]byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil && !errors.Is(err, zip.ErrInsecurePath) {
		t.Fatal(err)
	}
	var raw [][]byte
	for _, f := range zr.File {
		if strings.HasSuffix(f.Name, "/") {
			continue
		}
		r, err := f.OpenRaw()
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(r)
		raw = append(raw, b)
	}
	return raw
}

func TestUntouchedPackageKeepsEveryByte(t *testing.T) {
	for name, data := range fixtures(t) {
		t.Run(name, func(t *testing.T) {
			p, err := Open(data, Limits{})
			if err != nil {
				t.Fatal(err)
			}
			out, err := p.Bytes()
			if err != nil {
				t.Fatal(err)
			}
			q, err := Open(out, Limits{})
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(p.Names(), q.Names()) {
				t.Fatalf("names %v, then %v", p.Names(), q.Names())
			}
			if !slices.EqualFunc(rawEntries(t, data), rawEntries(t, out), bytes.Equal) {
				t.Error("compressed data changed")
			}
		})
	}
}

func TestSetAddRemove(t *testing.T) {
	p, err := Open(fixtures(t)["blank.docx"], Limits{})
	if err != nil {
		t.Fatal(err)
	}
	doc := []byte(`<w:document xmlns:w="w"/>`)
	if err := p.Set("word/document.xml", doc); err != nil {
		t.Fatal(err)
	}
	png := []byte("\x89PNG")
	if err := p.Add("word/media/image1.png", "image/png", png); err != nil {
		t.Fatal(err)
	}
	if err := p.Add("word/media/IMAGE1.png", "image/png", png); err == nil {
		t.Fatal("added a part twice under another case")
	}
	if err := p.Set("word/missing.xml", doc); !errors.Is(err, ErrNotFound) {
		t.Fatalf("set a missing part: %v", err)
	}

	q := reopen(t, p)
	if got, _ := q.Read("word/document.xml"); !bytes.Equal(got, doc) {
		t.Errorf("document.xml = %q", got)
	}
	if got, _ := q.Read("word/media/image1.png"); !bytes.Equal(got, png) {
		t.Errorf("image1.png = %q", got)
	}
	if ct := q.ContentType("word/media/image1.png"); ct != "image/png" {
		t.Errorf("content type %q", ct)
	}

	if err := q.Remove("word/media/image1.png"); err != nil {
		t.Fatal(err)
	}
	r := reopen(t, q)
	if r.Has("word/media/image1.png") || r.ContentType("word/media/image1.png") != "" {
		t.Error("removed part still there")
	}
	if !r.Has("word/document.xml") {
		t.Error("document.xml lost")
	}
}

func reopen(t *testing.T, p *Package) *Package {
	t.Helper()
	q, err := Open(mustBytes(t, p), Limits{})
	if err != nil {
		t.Fatal(err)
	}
	return q
}

func TestRelationships(t *testing.T) {
	p, err := Open(fixtures(t)["blank.docx"], Limits{})
	if err != nil {
		t.Fatal(err)
	}
	rels, err := p.Relationships("")
	if err != nil {
		t.Fatal(err)
	}
	var main string
	for _, r := range rels {
		if r.Type == "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" {
			main, _ = Resolve("", r.Target)
		}
	}
	if main != "word/document.xml" {
		t.Fatalf("main part %q in %+v", main, rels)
	}
	if ct := p.ContentType(main); ct != "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml" {
		t.Errorf("content type %q", ct)
	}
	if rels, err := p.Relationships(main); err != nil || rels != nil {
		t.Errorf("relationships of a part without any: %v, %v", rels, err)
	}
}

func TestExternalRelationship(t *testing.T) {
	data := makeZip(t,
		entry{contentTypesName, minimalTypes},
		entry{"word/_rels/document.xml.rels", `<Relationships xmlns="` + relsNamespace + `">` +
			`<Relationship Id="rId1" Type="t" Target="https://example.com/a.png" TargetMode="External"/>` +
			`<Relationship Id="rId2" Type="t" Target="media/a.png"/></Relationships>`},
	)
	p, err := Open(data, Limits{})
	if err != nil {
		t.Fatal(err)
	}
	rels, err := p.Relationships("word/document.xml")
	if err != nil {
		t.Fatal(err)
	}
	if len(rels) != 2 || !rels[0].External || rels[1].External {
		t.Fatalf("%+v", rels)
	}
}

func TestResolve(t *testing.T) {
	for _, c := range []struct{ source, target, want string }{
		{"", "word/document.xml", "word/document.xml"},
		{"", "/word/document.xml", "word/document.xml"},
		{"word/document.xml", "media/image1.png", "word/media/image1.png"},
		{"word/document.xml", "../customXml/item1.xml", "customXml/item1.xml"},
		{"ppt/slides/slide1.xml", "/ppt/media/a%20b.png", "ppt/media/a b.png"},
		{"word/document.xml", "../../../x.xml", "x.xml"},
	} {
		if got, err := Resolve(c.source, c.target); err != nil || got != c.want {
			t.Errorf("Resolve(%q, %q) = %q, %v; want %q", c.source, c.target, got, err, c.want)
		}
	}
	for _, target := range []string{"https://example.com/x", "//host/x", "", "a\\b"} {
		if got, err := Resolve("word/document.xml", target); err == nil {
			t.Errorf("Resolve(%q) = %q, want an error", target, got)
		}
	}
}

func TestOpenRejects(t *testing.T) {
	types := entry{contentTypesName, minimalTypes}
	for name, c := range map[string]struct {
		data   []byte
		limits Limits
		want   error
	}{
		"not a zip":         {[]byte("hello"), Limits{}, ErrInvalid},
		"no content types":  {makeZip(t, entry{"a.xml", "<a/>"}), Limits{}, ErrInvalid},
		"bad content types": {makeZip(t, entry{contentTypesName, "<Types/>"}), Limits{}, ErrInvalid},
		"parent segment":    {makeZip(t, types, entry{"../a.xml", ""}), Limits{}, ErrInvalid},
		"absolute":          {makeZip(t, types, entry{"/a.xml", ""}), Limits{}, ErrInvalid},
		"compound file":     {append(compoundSignature, 0, 0), Limits{}, ErrCompound},
		"empty segment":     {makeZip(t, types, entry{"a//b.xml", ""}), Limits{}, ErrInvalid},
		"duplicate":         {makeZip(t, types, entry{"a.xml", ""}, entry{"A.xml", ""}), Limits{}, ErrInvalid},
		"duplicate once normalized": {
			makeZip(t, types, entry{"a/b.xml", ""}, entry{"a\\b.xml", ""}), Limits{}, ErrInvalid,
		},
		"too many parts": {makeZip(t, types, entry{"a.xml", ""}), Limits{MaxParts: 1}, ErrTooLarge},
		"part too large": {
			makeZip(t, types, entry{"a.xml", minimalTypes + "!"}),
			Limits{MaxPartSize: int64(len(minimalTypes))}, ErrTooLarge,
		},
		"total too large": {
			makeZip(t, types, entry{"a.xml", "01234"}, entry{"b.xml", "01234"}),
			Limits{MaxTotalSize: int64(len(minimalTypes)) + 9}, ErrTooLarge,
		},
	} {
		if _, err := Open(c.data, c.limits); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
}

func TestBackslashesAreNormalized(t *testing.T) {
	types := strings.Replace(minimalTypes, "</Types>",
		`<Override PartName="/xl/sharedStrings.xml" ContentType="s"/></Types>`, 1)
	data := makeZip(t, entry{contentTypesName, types},
		entry{"xl\\styles.xml", "<a/>"}, entry{"xl\\sharedstrings.xml", "<s/>"})
	p, err := Open(data, Limits{})
	if err != nil {
		t.Fatal(err)
	}
	q := reopen(t, p)
	if got, err := q.Read("xl/styles.xml"); err != nil || string(got) != "<a/>" {
		t.Fatalf("xl/styles.xml = %q, %v", got, err)
	}
	if want := []string{contentTypesName, "xl/styles.xml", "xl/sharedStrings.xml"}; !slices.Equal(q.Names(), want) {
		t.Fatalf("names %q, want %q", q.Names(), want)
	}
	if !slices.EqualFunc(rawEntries(t, data), rawEntries(t, mustBytes(t, q)), bytes.Equal) {
		t.Error("compressed data changed")
	}
}

func mustBytes(t *testing.T, p *Package) []byte {
	t.Helper()
	out, err := p.Bytes()
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func TestLyingSizeIsCaughtOnRead(t *testing.T) {
	content := bytes.Repeat([]byte("a"), 1<<20)
	var deflated bytes.Buffer
	fw, _ := flate.NewWriter(&deflated, flate.BestCompression)
	fw.Write(content)
	fw.Close()

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create(contentTypesName)
	w.Write([]byte(minimalTypes))
	raw, err := zw.CreateRaw(&zip.FileHeader{
		Name: "bomb.xml", Method: zip.Deflate,
		CRC32: crc32.ChecksumIEEE(content), CompressedSize64: uint64(deflated.Len()), UncompressedSize64: 10,
	})
	if err != nil {
		t.Fatal(err)
	}
	raw.Write(deflated.Bytes())
	zw.Close()

	p, err := Open(buf.Bytes(), Limits{MaxPartSize: 1000})
	if err != nil {
		t.Fatal(err)
	}
	if got, err := p.Read("bomb.xml"); !errors.Is(err, ErrInvalid) {
		t.Fatalf("read %d bytes of a part declared as 10: %v", len(got), err)
	}
}

func FuzzOpen(f *testing.F) {
	for _, data := range fixtures(f) {
		f.Add(data)
	}
	f.Fuzz(func(t *testing.T, data []byte) {
		p, err := Open(data, Limits{MaxTotalSize: 16 << 20})
		if err != nil {
			return
		}
		for _, name := range p.Names() {
			p.Read(name)
			p.Relationships(name)
			p.ContentType(name)
		}
		out, err := p.Bytes()
		if err != nil {
			t.Fatal(err)
		}
		if _, err := Open(out, Limits{}); err != nil {
			t.Fatalf("written package does not open again: %v", err)
		}
	})
}

func BenchmarkOpenWrite(b *testing.B) {
	data := fixtures(b)["blank.pptx"]
	for b.Loop() {
		p, err := Open(data, Limits{})
		if err != nil {
			b.Fatal(err)
		}
		if _, err := p.Bytes(); err != nil {
			b.Fatal(err)
		}
	}
}
