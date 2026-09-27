package xlsx

import (
	"encoding/json"
	"math/rand/v2"
	"testing"
)

func TestMarshalFields(t *testing.T) {
	r := rand.New(rand.NewPCG(1, 2))
	alphabet := []rune{'a', 'Z', '"', '\\', '<', '>', '&', '\n', '\r', '\t', '\b', '\f', 0, 0x1f, 0x7f, 'é', '€', 0x2028, 0x2029, 0xfffd, '😀'}
	str := func() string {
		b := []byte{}
		for range r.IntN(6) {
			if r.IntN(12) == 0 {
				b = append(b, 0xff)
				continue
			}
			b = append(b, string(alphabet[r.IntN(len(alphabet))])...)
		}
		return string(b)
	}
	for range 2000 {
		f := cellFields{CA: r.IntN(2) == 0, CM: r.IntN(3), E: str(), F: str(), FA: str(), Rich: str(), S: str(), VM: r.IntN(2)}
		if r.IntN(2) == 0 {
			f.M = &[2]int{r.IntN(9), r.IntN(9)}
		}
		if r.IntN(2) == 0 {
			f.V = mustJSON(str())
		}
		if got, want := string(f.marshal()), string(mustJSON(f)); got != want {
			t.Fatalf("got %s, want %s", got, want)
		}
	}
	var f cellFields
	if err := json.Unmarshal((&cellFields{F: "SUM(A1:A2)", V: number(3)}).marshal(), &f); err != nil || f.F != "SUM(A1:A2)" {
		t.Fatal(f, err)
	}
}
