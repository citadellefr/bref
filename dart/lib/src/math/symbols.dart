/// What a piece of a formula is to its neighbors: it sets the room between
/// them.
enum Cls { ord, op, bin, rel, open, close, punct, inner }

/// The alphabet letters and digits are taken from.
enum Variant { normal, roman, bold, italic, boldItalic, script, fraktur, doubleStruck, sans, mono }

typedef Symbol = ({int rune, Cls cls});

Map<String, Symbol> _of(Cls cls, String pairs) {
  final words = pairs.trim().split(RegExp(r'\s+'));
  return {for (var k = 0; k + 1 < words.length; k += 2) words[k]: (rune: words[k + 1].runes.first, cls: cls)};
}

/// The symbols a command stands for.
final Map<String, Symbol> symbols = {
  ..._of(Cls.ord, '''
    alpha α beta β gamma γ delta δ epsilon ϵ varepsilon ε zeta ζ eta η theta θ vartheta ϑ iota ι kappa κ
    varkappa ϰ lambda λ mu μ nu ν xi ξ omicron ο pi π varpi ϖ rho ρ varrho ϱ sigma σ varsigma ς tau τ
    upsilon υ phi ϕ varphi φ chi χ psi ψ omega ω
    Gamma Γ Delta Δ Theta Θ Lambda Λ Xi Ξ Pi Π Sigma Σ Upsilon Υ Phi Φ Psi Ψ Omega Ω
    infty ∞ partial ∂ nabla ∇ forall ∀ exists ∃ nexists ∄ emptyset ∅ varnothing ∅ hbar ℏ hslash ℏ ell ℓ wp ℘
    Re ℜ Im ℑ aleph ℵ beth ℶ gimel ℷ daleth ℸ angle ∠ measuredangle ∡ sphericalangle ∢ triangle △
    square □ Box □ blacksquare ■ lozenge ◊ top ⊤ bot ⊥ neg ¬ lnot ¬ flat ♭ natural ♮
    sharp ♯ clubsuit ♣ diamondsuit ♢ heartsuit ♡ spadesuit ♠ prime ′ backprime ‵ backslash \\ surd √
    degree ° S § P ¶ copyright © pounds £ checkmark ✓ imath 𝚤 jmath 𝚥 eth ð complement ∁ mho ℧
    vert | Vert ‖ vdots ⋮ blacktriangle ▲ triangledown ▽ blacktriangledown ▼
    # # \$ \$ % % & & _ _ | ‖
  '''),
  ..._of(Cls.bin, '''
    pm ± mp ∓ times × div ÷ cdot ⋅ centerdot ⋅ ast ∗ star ⋆ circ ∘ bullet ∙ cap ∩ cup ∪ uplus ⊎ sqcap ⊓
    sqcup ⊔ vee ∨ lor ∨ wedge ∧ land ∧ setminus ∖ smallsetminus ∖ wr ≀ diamond ⋄ bigtriangleup △
    bigtriangledown ▽ triangleleft ◁ triangleright ▷ oplus ⊕ ominus ⊖ otimes ⊗ oslash ⊘ odot ⊙ bigcirc ◯
    dagger † ddagger ‡ amalg ⨿ ltimes ⋉ rtimes ⋊ boxplus ⊞ boxminus ⊟ boxtimes ⊠ boxdot ⊡ dotplus ∔
    intercal ⊺ barwedge ⊼ veebar ⊻ curlywedge ⋏ curlyvee ⋎ Cap ⋒ Cup ⋓ circledast ⊛ circledcirc ⊚
    circleddash ⊝ divideontimes ⋇
  '''),
  ..._of(Cls.rel, '''
    leq ≤ le ≤ geq ≥ ge ≥ neq ≠ ne ≠ equiv ≡ sim ∼ simeq ≃ approx ≈ cong ≅ propto ∝ varpropto ∝ ll ≪ gg ≫
    prec ≺ succ ≻ preceq ⪯ succeq ⪰ subset ⊂ supset ⊃ subseteq ⊆ supseteq ⊇ nsubseteq ⊈ nsupseteq ⊉
    subsetneq ⊊ supsetneq ⊋ sqsubset ⊏ sqsupset ⊐ sqsubseteq ⊑ sqsupseteq ⊒ in ∈ notin ∉ ni ∋ owns ∋
    vdash ⊢ dashv ⊣ models ⊨ vDash ⊨ Vdash ⊩ perp ⟂ mid ∣ nmid ∤ parallel ∥ nparallel ∦ asymp ≍ doteq ≐
    bowtie ⋈ smile ⌣ frown ⌢ leqslant ⩽ geqslant ⩾ lesssim ≲ gtrsim ≳ lessapprox ⪅ gtrapprox ⪆ lessgtr ≶
    gtrless ≷ nless ≮ ngtr ≯ nleq ≰ ngeq ≱ approxeq ≊ triangleq ≜ coloneqq ≔ eqqcolon ≕ therefore ∴
    because ∵ between ≬ lll ⋘ ggg ⋙ nsim ≁ ncong ≇ nprec ⊀ nsucc ⊁ lhd ⊲ rhd ⊳ unlhd ⊴ unrhd ⊵
    vartriangleleft ⊲ vartriangleright ⊳ trianglelefteq ⊴ trianglerighteq ⊵ multimap ⊸
    backsim ∽ eqsim ≂ nequiv ≢ lessdot ⋖ gtrdot ⋗ leqq ≦ geqq ≧ lneq ⪇ gneq ⪈ precsim ≾ succsim ≿
    leftarrow ← gets ← rightarrow → to → leftrightarrow ↔ Leftarrow ⇐ Rightarrow ⇒ Leftrightarrow ⇔
    iff ⟺ implies ⟹ impliedby ⟸ mapsto ↦ longmapsto ⟼ longleftarrow ⟵ longrightarrow ⟶
    longleftrightarrow ⟷ Longleftarrow ⟸ Longrightarrow ⟹ Longleftrightarrow ⟺ uparrow ↑ downarrow ↓
    updownarrow ↕ Uparrow ⇑ Downarrow ⇓ Updownarrow ⇕ nearrow ↗ searrow ↘ swarrow ↙ nwarrow ↖
    hookleftarrow ↩ hookrightarrow ↪ leftharpoonup ↼ leftharpoondown ↽ rightharpoonup ⇀
    rightharpoondown ⇁ rightleftharpoons ⇌ leftrightharpoons ⇋ leadsto ⇝ rightsquigarrow ⇝
    twoheadrightarrow ↠ twoheadleftarrow ↞ rightarrowtail ↣ leftarrowtail ↢ nrightarrow ↛ nleftarrow ↚
    nRightarrow ⇏ nLeftarrow ⇍ nLeftrightarrow ⇎ nleftrightarrow ↮ circlearrowleft ↺ circlearrowright ↻
    curvearrowleft ↶ curvearrowright ↷ upharpoonright ↾ restriction ↾ downharpoonright ⇂ upharpoonleft ↿
    downharpoonleft ⇃ leftleftarrows ⇇ rightrightarrows ⇉ leftrightarrows ⇆ rightleftarrows ⇄
    Lleftarrow ⇚ Rrightarrow ⇛
  '''),
  ..._of(Cls.open, 'lbrace { { { lbrack [ langle ⟨ lfloor ⌊ lceil ⌈ lgroup ⟮ llbracket ⟦ lvert | lVert ‖ ulcorner ⌜ llcorner ⌞'),
  ..._of(Cls.close, 'rbrace } } } rbrack ] rangle ⟩ rfloor ⌋ rceil ⌉ rgroup ⟯ rrbracket ⟧ rvert | rVert ‖ urcorner ⌝ lrcorner ⌟'),
  ..._of(Cls.punct, 'colon : ldotp . cdotp ⋅'),
  ..._of(Cls.op, '''
    sum ∑ prod ∏ coprod ∐ bigcup ⋃ bigcap ⋂ bigvee ⋁ bigwedge ⋀ bigoplus ⨁ bigotimes ⨂ bigodot ⨀
    biguplus ⨄ bigsqcup ⨆ int ∫ iint ∬ iiint ∭ iiiint ⨌ oint ∮ oiint ∯ oiiint ∰
  '''),
  ..._of(Cls.inner, 'ldots … dots … dotsc … dotso … cdots ⋯ dotsb ⋯ dotsm ⋯ dotsi ⋯ ddots ⋱'),
};

/// Whether the limits of the operator [rune] go beside it even on a line
/// of its own: those of integrals do.
bool besideLimits(int rune) => rune >= 0x222B && rune <= 0x2233 || rune == 0x2A0C;

/// The class of the characters typed as they are.
final Map<int, Cls> classes = {
  for (final s in symbols.values)
    if (s.rune > 0x7F) s.rune: s.cls,
  0x2B: Cls.bin,
  0x2212: Cls.bin,
  0x2217: Cls.bin,
  0x3D: Cls.rel,
  0x3C: Cls.rel,
  0x3E: Cls.rel,
  0x3A: Cls.rel,
  0x2C: Cls.punct,
  0x3B: Cls.punct,
  0x21: Cls.close,
  0x3F: Cls.close,
  0x28: Cls.open,
  0x5B: Cls.open,
  0x29: Cls.close,
  0x5D: Cls.close,
};

/// The functions named in upright letters; those of the second list take
/// their limits under them on a line of their own.
const functions = {
  'arccos', 'arcsin', 'arctan', 'arcctg', 'arctg', 'arg', 'ch', 'cos', 'cosec', 'cosh', 'cot', 'cotg', 'coth', 'csc',
  'ctg', 'cth', 'deg', 'dim', 'exp', 'hom', 'ker', 'lg', 'ln', 'log', 'sec', 'sh', 'sin', 'sinh', 'tan', 'tanh',
  'tg', 'th',
};

const limitFunctions = {
  'det': 'det', 'gcd': 'gcd', 'inf': 'inf', 'lim': 'lim', 'liminf': 'lim inf', 'limsup': 'lim sup', 'max': 'max',
  'min': 'min', 'Pr': 'Pr', 'sup': 'sup', 'argmax': 'arg max', 'argmin': 'arg min', 'injlim': 'inj lim',
  'projlim': 'proj lim',
};

/// The accents set over what they take, by command; the wide ones stretch.
const accents = {
  'hat': 0x302, 'check': 0x30C, 'tilde': 0x303, 'acute': 0x301, 'grave': 0x300, 'dot': 0x307, 'ddot': 0x308,
  'dddot': 0x20DB, 'breve': 0x306, 'bar': 0x304, 'vec': 0x20D7, 'mathring': 0x30A,
};

const wideAccents = {
  'widehat': 0x302, 'widetilde': 0x303, 'widecheck': 0x30C, 'overrightarrow': 0x20D7, 'overleftarrow': 0x20D6,
  'overleftrightarrow': 0x20E1, 'overbrace': 0x23DE, 'overparen': 0x23DC, 'overbracket': 0x23B4,
};

const underAccents = {
  'underbrace': 0x23DF, 'underparen': 0x23DD, 'underbracket': 0x23B5, 'underrightarrow': 0x20EF,
  'underleftarrow': 0x20EE,
};

/// The arrows that stretch to what is written over and under them.
const stretchArrows = {
  'xrightarrow': 0x2192, 'xleftarrow': 0x2190, 'xleftrightarrow': 0x2194, 'xRightarrow': 0x21D2, 'xLeftarrow': 0x21D0,
  'xLeftrightarrow': 0x21D4, 'xmapsto': 0x21A6, 'xhookrightarrow': 0x21AA, 'xhookleftarrow': 0x21A9,
  'xtwoheadrightarrow': 0x21A0, 'xrightharpoonup': 0x21C0, 'xrightleftharpoons': 0x21CC, 'xlongequal': 0x3D,
};

/// What `\not` makes of the relation after it, when the font has it whole.
const negated = {
  0x3D: 0x2260, 0x3C: 0x226E, 0x3E: 0x226F, 0x2208: 0x2209, 0x220B: 0x220C, 0x2261: 0x2262, 0x223C: 0x2241,
  0x2243: 0x2244, 0x2245: 0x2247, 0x2248: 0x2249, 0x2264: 0x2270, 0x2265: 0x2271, 0x2282: 0x2284, 0x2283: 0x2285,
  0x2286: 0x2288, 0x2287: 0x2289, 0x2223: 0x2224, 0x2225: 0x2226, 0x2203: 0x2204,
};

const _alphabets = <Variant, (int upper, int lower, int digit, int upperGreek, int lowerGreek)>{
  Variant.bold: (0x1D400, 0x1D41A, 0x1D7CE, 0x1D6A8, 0x1D6C2),
  Variant.italic: (0x1D434, 0x1D44E, 0, 0x1D6E2, 0x1D6FC),
  Variant.boldItalic: (0x1D468, 0x1D482, 0x1D7CE, 0x1D71C, 0x1D736),
  Variant.script: (0x1D49C, 0x1D4B6, 0, 0, 0),
  Variant.fraktur: (0x1D504, 0x1D51E, 0, 0, 0),
  Variant.doubleStruck: (0x1D538, 0x1D552, 0x1D7D8, 0, 0),
  Variant.sans: (0x1D5A0, 0x1D5BA, 0x1D7E2, 0, 0),
  Variant.mono: (0x1D670, 0x1D68A, 0x1D7F6, 0, 0),
};

/// The letters Unicode put elsewhere than in the alphabet they belong to.
const _moved = {
  0x1D455: 0x210E, 0x1D49D: 0x212C, 0x1D4A0: 0x2130, 0x1D4A1: 0x2131, 0x1D4A3: 0x210B, 0x1D4A4: 0x2110,
  0x1D4A7: 0x2112, 0x1D4A8: 0x2133, 0x1D4AD: 0x211B, 0x1D4BA: 0x212F, 0x1D4BC: 0x210A, 0x1D4C4: 0x2134,
  0x1D506: 0x212D, 0x1D50B: 0x210C, 0x1D50C: 0x2111, 0x1D515: 0x211C, 0x1D51D: 0x2128, 0x1D53A: 0x2102,
  0x1D53F: 0x210D, 0x1D545: 0x2115, 0x1D547: 0x2119, 0x1D548: 0x211A, 0x1D549: 0x211D, 0x1D551: 0x2124,
};

/// The Greek letters that follow ω in the alphabets of Unicode, in order.
const _afterOmega = [0x2202, 0x3F5, 0x3D1, 0x3F0, 0x3D5, 0x3F1, 0x3D6];

/// The character that shows [rune] in the alphabet of [variant]: letters
/// are slanted unless told otherwise, but the Greek capitals.
int styled(int rune, Variant variant) {
  final upper = rune >= 0x41 && rune <= 0x5A, lower = rune >= 0x61 && rune <= 0x7A;
  final upperGreek = rune >= 0x391 && rune <= 0x3A9, lowerGreek = rune >= 0x3B1 && rune <= 0x3C9;
  final extra = variant == Variant.normal && rune == 0x2202 ? -1 : _afterOmega.indexOf(rune);
  if (variant == Variant.normal) {
    if (upperGreek || !(upper || lower || lowerGreek || extra >= 0)) return rune;
    variant = Variant.italic;
  }
  final a = _alphabets[variant];
  if (a == null) return rune;
  final (upperBase, lowerBase, digitBase, upperGreekBase, lowerGreekBase) = a;
  var out = rune;
  if (upper) {
    out = upperBase + rune - 0x41;
  } else if (lower) {
    out = lowerBase + rune - 0x61;
  } else if (rune >= 0x30 && rune <= 0x39 && digitBase != 0) {
    out = digitBase + rune - 0x30;
  } else if (upperGreek && upperGreekBase != 0) {
    out = upperGreekBase + rune - 0x391;
  } else if (lowerGreek && lowerGreekBase != 0) {
    out = lowerGreekBase + rune - 0x3B1;
  } else if (extra >= 0 && lowerGreekBase != 0) {
    out = lowerGreekBase + 25 + extra;
  }
  return _moved[out] ?? out;
}
