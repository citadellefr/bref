package formula

// Locale is how a workbook's user writes numbers and dates: what text
// converts to a number, and what TEXT and the formats write.
type Locale struct {
	Decimal string
	// Groups separate thousands, the first one written.
	Groups []string
	// DayFirst reads 01/02/2024 as the 1st of February.
	DayFirst bool
	Currency string
	// True and False are how booleans read as text.
	True, False string
}

// French is the locale of France, whose Excel groups thousands with a
// narrow no-break space and takes the others when reading.
var French = &Locale{Decimal: ",", Groups: []string{"\u202f", "\u00a0", " "}, DayFirst: true, Currency: "€", True: "VRAI", False: "FAUX"}

// English is the locale of the United States.
var English = &Locale{Decimal: ".", Groups: []string{","}, Currency: "$", True: "TRUE", False: "FALSE"}
