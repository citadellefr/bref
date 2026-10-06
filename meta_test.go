package bref

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/citadellefr/trame"
	"github.com/citadellefr/trame/trametest"
)

const newThread = `{"o":"new","id":"t1","t":"thread","k":"V"},` +
	`{"o":"new","id":"m1","t":"msg","p":"t1","k":"V","a":{"by":"1","name":"Alice","text":"Why?"}}`

func TestCommentsAreKeptBesideTheNote(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("Hello wide world")
	h := NewHub(store, fast)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Name: "Alice", Client: "a"})

	// "wide" is what the thread is about, and Alice types a word before it
	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":6},{"r":4,"a":{"c.t1":"1"}}]},` + newThread + `]}`)
	alice.Expect("ack")
	f := alice.Expect("op")
	if f.SID != 0 || !strings.Contains(string(f.D), `"o":"set","id":"m1","a":{"at":`) {
		t.Fatalf("the server dates the message: %s", f.D)
	}
	alice.Send(`{"t":"op","n":2,"v":2,"d":[{"o":"txt","id":"body","x":[{"r":6},{"i":"very ","a":{"by":"1"}}]}]}`)
	alice.Expect("ack")
	<-store.Saves
	alice.Expect("saved")
	alice.Leave()

	var m metaNote
	if err := json.Unmarshal(store.Meta["n.md"], &m); err != nil {
		t.Fatal(err)
	}
	if len(m.Threads) != 1 || m.Threads[0].Ranges[0] != [2]int{11, 15} || m.Threads[0].Msgs[0].Text != "Why?" ||
		m.Threads[0].Msgs[0].At == 0 || m.By[0] != (metaRun{6, 11, "1"}) {
		t.Fatalf("meta = %s", store.Meta["n.md"])
	}

	bob, _, doc := join(t, h, "n.md", trame.Peer{ID: "2", Name: "Bob", Client: "b"})
	for _, want := range []string{`"id":"t1","t":"thread"`, `"x":[{"i":"Hello "},{"i":"very ","a":{"by":"1"}},{"i":"wide","a":{"c.t1":"1"}}`, `"id":"m1","t":"msg","p":"t1"`} {
		if !strings.Contains(string(doc.D), want) {
			t.Fatalf("reopened without %s: %s", want, doc.D)
		}
	}
	bob.Quiet()
}

func TestCommentsAreRefusedWhereNothingKeepsThem(t *testing.T) {
	store := trametest.NewStore()
	h := NewHub(struct{ trame.Store }{store}, fast)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Name: "Alice", Client: "a"})
	alice.Send(`{"t":"op","n":1,"v":0,"d":[` + newThread + `]}`)
	alice.Expect("nack")
	alice.Send(`{"t":"op","n":2,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":1,"a":{"c.t1":"1"}}]}]}`)
	alice.Expect("nack")
}

func TestCommentsBelongToTheirAuthor(t *testing.T) {
	store := trametest.NewStore()
	h := NewHub(store, fast)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Name: "Alice", Client: "a"})
	bob, _, _ := join(t, h, "n.md", trame.Peer{ID: "2", Name: "Bob", Client: "b"})
	alice.Expect("join")

	alice.Send(`{"t":"op","n":1,"v":0,"d":[` + newThread + `]}`)
	alice.Expect("ack")
	alice.Expect("op")
	bob.Expect("op")
	bob.Expect("op")

	for i, op := range []string{
		// signed as someone else
		`{"o":"new","id":"m2","t":"msg","p":"t1","k":"W","a":{"by":"1","name":"Alice","text":"hi"}}`,
		// dated by the client
		`{"o":"new","id":"m2","t":"msg","p":"t1","k":"W","a":{"by":"2","name":"Bob","text":"hi","at":"1"}}`,
		// somewhere else than a thread
		`{"o":"new","id":"m2","t":"msg","p":"body","k":"W","a":{"by":"2","name":"Bob","text":"hi"}}`,
		// the message of another
		`{"o":"set","id":"m1","a":{"text":"mine"}}`,
		`{"o":"del","id":"m1"}`,
		// a thread with the message of another
		`{"o":"del","id":"t1"}`,
		// anything else
		`{"o":"set","id":"t1","a":{"x":"1"}}`,
	} {
		bob.Send(`{"t":"op","n":` + string(rune('1'+i)) + `,"v":2,"d":[` + op + `]}`)
		if f := bob.Expect("nack"); f.Error == "" {
			t.Fatalf("%s: %+v", op, f)
		}
	}

	// resolving is for everyone, answering too
	bob.Send(`{"t":"op","n":8,"v":2,"d":[{"o":"set","id":"t1","a":{"done":true}},` +
		`{"o":"new","id":"m2","t":"msg","p":"t1","k":"W","a":{"by":"2","name":"Bob","text":"Because"}}]}`)
	bob.Expect("ack")
	bob.Expect("op")
	alice.Expect("op")
	alice.Expect("op")
	alice.Send(`{"t":"op","n":2,"v":4,"d":[{"o":"del","id":"m1"}]}`)
	alice.Expect("ack")
}

func TestNotesChangedBesideTheirMetaKeepWhatCanBeKept(t *testing.T) {
	store := trametest.NewStore()
	store.Data["n.md"] = []byte("one two three")
	h := NewHub(store, fast)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Name: "Alice", Client: "a"})
	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"r":4},{"r":3,"a":{"c.t1":"1"}},{"r":6},{"i":"!","a":{"by":"1"}}]},` + newThread + `]}`)
	alice.Expect("ack")
	alice.Expect("op")
	<-store.Saves
	alice.Expect("saved")
	alice.Leave()

	// someone rewrote the end of the file, and the start
	store.Data["n.md"] = []byte("1 one two 3 four")
	_, _, doc := join(t, h, "n.md", trame.Peer{ID: "2", Name: "Bob", Client: "b"})
	if !strings.Contains(string(doc.D), `{"i":"two","a":{"c.t1":"1"}}`) || strings.Contains(string(doc.D), `{"by"`) {
		t.Fatalf("doc = %s", doc.D)
	}
}

func TestVersionsAreToldWithTheirEditors(t *testing.T) {
	store := trametest.NewStore()
	type saved struct {
		data    string
		authors []string
	}
	got := make(chan saved, 4)
	opt := fast
	opt.OnSave = func(_ string, data []byte, authors []string) { got <- saved{string(data), authors} }
	h := NewHub(store, opt)
	alice, _, _ := join(t, h, "n.md", trame.Peer{ID: "1", Client: "a"})
	bob, _, _ := join(t, h, "n.md", trame.Peer{ID: "2", Client: "b"})
	alice.Expect("join")
	alice.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"a"}]}]}`)
	bob.Send(`{"t":"op","n":1,"v":0,"d":[{"o":"txt","id":"body","x":[{"i":"b"}]}]}`)
	s := <-got
	if len(s.authors) != 2 || s.authors[0] != "1" || s.authors[1] != "2" || !strings.ContainsAny(s.data, "ab") {
		t.Fatalf("saved %+v", s)
	}
}
