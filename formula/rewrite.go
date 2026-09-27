package formula

import (
	"strings"
)

// Rewrite gives each reference of f to change, and writes back those it
// changed; the rest of f is kept as written.
func Rewrite(f string, change func(r *Ref) bool) (string, error) {
	tokens, err := Tokens(f)
	if err != nil {
		return f, err
	}
	var b strings.Builder
	last := 0
	for _, t := range tokens {
		if t.Kind != Reference || !change(t.Ref) {
			continue
		}
		b.WriteString(f[last:t.Pos])
		b.WriteString(t.Ref.String())
		last = t.Pos + len(t.Text)
	}
	if last == 0 {
		return f, nil
	}
	b.WriteString(f[last:])
	return b.String(), nil
}

// Translate is f copied dr rows down and dc columns right: its relative
// references move, those that leave the sheet become #REF!.
func Translate(f string, dr, dc int) (string, error) {
	if dr == 0 && dc == 0 {
		return f, nil
	}
	return Rewrite(f, func(r *Ref) bool {
		if r.Invalid {
			return false
		}
		a := r.Area
		ok := true
		if !a.Cols {
			ok = move(&a.R1, a.AbsR1, dr, MaxRows) && move(&a.R2, a.AbsR2, dr, MaxRows)
		}
		if !a.Rows {
			ok = ok && move(&a.C1, a.AbsC1, dc, MaxCols) && move(&a.C2, a.AbsC2, dc, MaxCols)
		}
		if !ok {
			r.Invalid = true
			return true
		}
		changed := a != r.Area
		r.Area = a.normal()
		return changed
	})
}

func move(i *int, abs bool, d, limit int) bool {
	if abs {
		return true
	}
	*i += d
	return *i >= 1 && *i <= limit
}

// Shift is f once n rows (or columns, when rows is false) are inserted at
// at on the sheet named sheet, or removed when n is negative. own tells
// whether f lives on that sheet, where its references name no sheet.
// References to removed cells become #REF!.
func Shift(f, sheet string, own, rows bool, at, n int) (string, error) {
	return Rewrite(f, func(r *Ref) bool {
		if r.Invalid || r.Book != "" || r.LastSheet != "" {
			return false
		}
		if r.Sheet == "" && !own || r.Sheet != "" && !strings.EqualFold(r.Sheet, sheet) {
			return false
		}
		a := r.Area
		var ok bool
		if rows {
			if a.Cols {
				return false
			}
			a.R1, a.R2, ok = shiftSpan(a.R1, a.R2, at, n, MaxRows)
		} else {
			if a.Rows {
				return false
			}
			a.C1, a.C2, ok = shiftSpan(a.C1, a.C2, at, n, MaxCols)
		}
		if !ok {
			r.Invalid = true
			return true
		}
		if a == r.Area {
			return false
		}
		r.Area = a
		return true
	})
}

// shiftSpan moves the span lo to hi as inserting n at at, or removing -n,
// does; false when nothing is left of it.
func shiftSpan(lo, hi, at, n, limit int) (int, int, bool) {
	if n > 0 {
		if lo >= at {
			lo += n
		}
		if hi >= at {
			hi = min(hi+n, limit)
		}
		return lo, hi, lo <= limit
	}
	end := at - n
	switch {
	case lo >= end:
		lo += n
	case lo >= at:
		lo = at
	}
	switch {
	case hi >= end:
		hi += n
	case hi >= at:
		hi = at - 1
	}
	return lo, hi, lo <= hi
}

// Rename is f with its references to the sheet old pointing to new.
func Rename(f, old, new string) (string, error) {
	return Rewrite(f, func(r *Ref) bool {
		if r.Book != "" || !strings.EqualFold(r.Sheet, old) && !strings.EqualFold(r.LastSheet, old) {
			return false
		}
		if strings.EqualFold(r.Sheet, old) {
			r.Sheet = new
		}
		if strings.EqualFold(r.LastSheet, old) {
			r.LastSheet = new
		}
		return true
	})
}

// Drop is f once the sheet named sheet is deleted: its references to it
// become #REF!.
func Drop(f, sheet string) (string, error) {
	return Rewrite(f, func(r *Ref) bool {
		if r.Book != "" || !strings.EqualFold(r.Sheet, sheet) && !strings.EqualFold(r.LastSheet, sheet) {
			return false
		}
		*r = Ref{Invalid: true}
		return true
	})
}
