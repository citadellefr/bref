package pagination

import "unicode"

// wordBreaks lists where Word's last layout started pages, by key.
func wordBreaks(d *Doc, key func(Pos) Pos) map[Pos]bool {
	word := map[Pos]bool{}
	var walk func([]Block)
	walk = func(blocks []Block) {
		for _, b := range blocks {
			switch b := b.(type) {
			case *Para:
				for _, off := range b.WordBreaks {
					word[key(Pos{Para: b.Index, Offset: off})] = true
				}
			case *Table:
				for _, row := range b.Rows {
					for _, c := range row.Cells {
						walk(c.Blocks)
					}
				}
			}
		}
	}
	walk(d.Body)
	return word
}

// anonymized tells whether most letters of the document are "x": bug
// reports often replace the text so, which leaves Word's page breaks those
// of a text that is gone.
func anonymized(d *Doc) bool {
	letters, xs := 0, 0
	var walk func([]Block)
	walk = func(blocks []Block) {
		for _, b := range blocks {
			switch b := b.(type) {
			case *Para:
				for _, it := range b.Items {
					for _, r := range it.Text {
						if unicode.IsLetter(r) {
							letters++
							if r == 'x' || r == 'X' {
								xs++
							}
						}
					}
				}
			case *Table:
				for _, row := range b.Rows {
					for _, c := range row.Cells {
						walk(c.Blocks)
					}
				}
			}
		}
	}
	walk(d.Body)
	return xs > letters/2
}
