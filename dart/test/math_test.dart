import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bref/src/math/font.dart';
import 'package:bref/src/math/parse.dart';
import 'package:bref/src/math/symbols.dart';
import 'package:bref/src/math/typeset.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final font = MathFont.parse(File('fonts/latinmodern-math.otf').readAsBytesSync().buffer.asByteData());

  Formula set(String tex, {bool display = false}) =>
      typeset(tex, font, size: 20, display: display, text: const TextStyle(color: Color(0xFF000000)), error: const Color(0xFFFF0000));

  test('the font gives its glyphs, their outlines and what its MATH table says', () {
    expect(font.unitsPerEm, 1000);
    expect(font[MathConstant.axisHeight], 250);
    expect(font[MathConstant.fractionRuleThickness], 40);
    expect(font[MathConstant.radicalKernAfterDegree], -556);
    expect(font.scriptPercent, 70);
    expect(font.radicalDegreeRaisePercent, 60);
    expect(font.glyph(0x4F60), 0);

    final x = font.glyph(0x78);
    expect(font.advance(x), 528);
    final shape = font.shape(x);
    expect([shape.left, shape.right, shape.height, shape.depth], [12, 516, 431, 0]);
    expect(font.shape(font.glyph(0x222B)).depth, 306);

    final f = font.glyph(0x1D453);
    expect(font.italic(f), 90);
    expect(font.accent(f), 464);
    expect(font.italic(x), 16);
    expect(font.italic(font.glyph(0x1D465)), 0);

    final paren = font.construction(font.glyph(0x28))!;
    expect(paren.variants.length, 8);
    expect(paren.variants.last.advance, 2991);
    expect(paren.parts.map((p) => p.extender), [false, true, false]);
    expect(font.construction(font.glyph(0x302), horizontal: true)!.parts, isEmpty);
    expect(font.construction(x), isNull);
  });

  test('a font that is not one is refused', () {
    expect(() => MathFont.parse(ByteData(64)), throwsFormatException);
    final cut = File('fonts/latinmodern-math.otf').readAsBytesSync().sublist(0, 4000);
    expect(() => MathFont.parse(cut.buffer.asByteData()), throwsFormatException);
  });

  test('the font has every symbol a command names', () {
    final runes = {
      for (final s in symbols.values) s.rune,
      ...accents.values,
      ...wideAccents.values,
      ...underAccents.values,
      ...stretchArrows.values,
      ...negated.values,
      0x221A,
      0x338,
      0x2032,
    };
    expect([for (final r in runes) if (font.glyph(r) == 0) r.toRadixString(16)], isEmpty);
    final lacking = [
      for (final v in Variant.values)
        for (final r in 'AZazhRCeg09ΓΩαωϵϑ∂'.runes)
          if (font.glyph(styled(r, v)) == 0) '${v.name} ${String.fromCharCode(r)}',
    ];
    expect(lacking, ['script a', 'script z', 'script h', 'script e', 'script g']);
    expect(set(r'\mathcal{a}').width, set(r'\mathrm{a}').width);
  });

  test('letters are slanted, but the Greek capitals, the digits and what is said upright', () {
    expect(styled(0x78, Variant.normal), 0x1D465);
    expect(styled(0x68, Variant.normal), 0x210E);
    expect(styled(0x393, Variant.normal), 0x393);
    expect(styled(0x3B1, Variant.normal), 0x1D6FC);
    expect(styled(0x3F5, Variant.normal), 0x1D716);
    expect(styled(0x2202, Variant.normal), 0x2202);
    expect(styled(0x32, Variant.normal), 0x32);
    expect(styled(0x78, Variant.roman), 0x78);
    expect(styled(0x52, Variant.doubleStruck), 0x211D);
    expect(styled(0x32, Variant.bold), 0x1D7D0);
    expect(styled(0x4C, Variant.script), 0x2112);
  });

  test('reads scripts, fractions, roots and what delimiters hold', () {
    final scripts = parseMath("x_i^{2}'").single as Scripts;
    expect((scripts.base! as Sym).rune, 0x1D465);
    expect(scripts.sub!.length, 1);
    expect(scripts.sup!.length, 1);
    expect(scripts.primes, 1);

    final frac = parseMath(r'\frac12').single as Frac;
    expect((frac.num.single as Sym).rune, 0x31);
    expect((frac.den.single as Sym).rune, 0x32);
    expect((parseMath(r'a \over b').single as Frac).rule, isTrue);

    final root = parseMath(r'\sqrt[3]{x+1}').single as Radical;
    expect(root.index!.length, 1);
    expect(root.body.length, 3);

    final held = parseMath(r'\left( a \middle| b \right]').single as Delimited;
    expect([held.left, held.middles.single, held.right], [0x28, 0x7C, 0x5D]);
    expect(held.parts.length, 2);
    expect((parseMath(r'\left\{ a').single as Delimited).right, 0);

    expect((parseMath('-').single as Sym).rune, 0x2212);
    expect((parseMath(r'\leq').single as Sym).cls, Cls.rel);
    expect((parseMath('≤').single as Sym).cls, Cls.rel);
    expect((parseMath(r'\not=').single as Sym).rune, 0x2260);
    expect(parseMath(r'\text{si } x').first, isA<TextNode>().having((t) => t.text, 'text', 'si '));
    expect(parseMath(r'\operatorname*{arg\,max}').single, isA<OpName>().having((o) => o.name, 'name', 'arg max'));
    expect(parseMath('a % rien\nb').length, 2);
  });

  test('reads rows and cells, in an environment or not', () {
    final rows = (parseMath(r'a &= b \\ c &= d \\').single as Table).rows;
    expect([for (final r in rows) r.length], [2, 2]);
    final matrix = parseMath(r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}').single as Delimited;
    expect((matrix.parts.single.single as Table).rows.length, 2);
    final cases = parseMath(r'\begin{cases} 1 & x > 0 \\ 0 \end{cases}').single as Delimited;
    expect([cases.left, cases.right], [0x7B, 0]);
    expect((parseMath(r'\begin{array}{l|r} a & b \end{array}').single as Table).aligns, 'lr');
  });

  test('what it does not know is kept as written, and nothing makes it fail', () {
    expect(parseMath(r'\inconnu x').first, isA<Bad>().having((b) => b.text, 'text', r'\inconnu'));
    expect(parseMath('a } b').whereType<Bad>().single.text, '}');
    expect(parseMath(r'\right)').first, isA<Bad>());
    expect(parseMath(r'\frac{a}{'), hasLength(1));
    expect(parseMath('^'), hasLength(1));
    expect(parseMath(r'\'), hasLength(1));
    expect(parseMath(''), isEmpty);
    final deep = parseMath('{' * 5000);
    expect(deep, hasLength(1));
    expect(set('{' * 5000).width, greaterThan(0));
  });

  test('a fraction stands on the axis, scripts are smaller and a root covers what it holds', () {
    final a = set('a'), frac = set(r'\frac{a}{b}'), display = set(r'\frac{a}{b}', display: true);
    expect(frac.height, greaterThan(a.height));
    expect(frac.depth, greaterThan(0));
    expect(display.height + display.depth, greaterThan(frac.height + frac.depth));

    final x = set('x'), squared = set('x^2'), both = set('x_i^2');
    expect(squared.height, greaterThan(x.height));
    expect(squared.width, lessThan(x.width + set('2').width));
    expect(both.depth, greaterThan(0));
    expect(both.width, lessThan(squared.width + set('i').width));

    final root = set(r'\sqrt{x}');
    expect(root.width, greaterThan(x.width));
    expect(root.height, greaterThan(x.height));
    expect(set(r'\sqrt{\frac{a}{b}}', display: true).height, greaterThan(display.height));
  });

  test('operators take their limits over and under on a line of their own, integrals beside', () {
    final inline = set(r'\sum_{i=1}^n'), display = set(r'\sum_{i=1}^n', display: true);
    expect(display.width, lessThan(inline.width));
    expect(display.height + display.depth, greaterThan(2 * (inline.height + inline.depth) - 10));
    expect(set(r'\int_0^1', display: true).width, greaterThan(set(r'\int', display: true).width));
    expect(set(r'\int\limits_0^1', display: true).width, moreOrLessEquals(set(r'\int', display: true).width, epsilon: 1));
    expect(set(r'\lim_{x \to 0}', display: true).depth, greaterThan(set(r'\lim_{x \to 0}').depth));
  });

  test('delimiters grow with what they hold, by variants then by parts', () {
    double tall(String tex) {
      final f = set(tex, display: true);
      return f.height + f.depth;
    }

    final plain = tall(r'\left( x \right)');
    expect(plain, moreOrLessEquals(tall('(x)'), epsilon: 0.01));
    final two = tall(r'\left( \frac{a}{b} \right)');
    expect(two, greaterThan(plain * 1.5));
    final many = tall(r'\left( \begin{matrix} a \\ b \\ c \\ d \\ e \\ f \\ g \\ h \end{matrix} \right)');
    expect(many, greaterThan(8 * 1.2 * 20 * 0.9));
    expect(tall(r'\Bigg('), greaterThan(tall(r'\big(')));
    expect(set(r'\left. x \right.').width, greaterThan(set('x').width));
  });

  test('the room between two pieces is that of their classes', () {
    double width(String tex) => set(tex).width;
    final a = width('a'), b = width('b');
    expect(width('ab'), moreOrLessEquals(a + b, epsilon: 0.01));
    expect(width('a+b') - a - b - width('+'), moreOrLessEquals(2 * 4 * 20 / 18, epsilon: 0.01));
    expect(width('a=b') - a - b - width('='), moreOrLessEquals(2 * 5 * 20 / 18, epsilon: 0.01));
    expect(width('-b'), moreOrLessEquals(width('-') + b, epsilon: 0.01));
    expect(width('a,b') - a - b - width(','), moreOrLessEquals(3 * 20 / 18, epsilon: 0.01));
    expect(width(r'a\,b') - a - b, moreOrLessEquals(3 * 20 / 18, epsilon: 0.01));
    expect(width(r'a\quad b') - a - b, moreOrLessEquals(20, epsilon: 0.01));
    expect(width(r'\sin x'), greaterThan(width(r'\sin') + width('x')));
    expect(width('x^{a+b}'), lessThan(width('x') + 0.7 * width('a+b')));
  });

  test('cells line up in their columns, and lines on their relation', () {
    final matrix = set(r'\begin{matrix} a & b \\ c & d \end{matrix}', display: true);
    expect(matrix.height + matrix.depth, moreOrLessEquals(2 * 1.2 * 20, epsilon: 1));
    expect(matrix.height - matrix.depth, moreOrLessEquals(2 * 0.25 * 20, epsilon: 0.01));
    final lines = set(r'a &= b \\ ccc &= d', display: true);
    expect(lines.width, moreOrLessEquals(set('ccc = d').width, epsilon: 0.5));
  });

  test('accents, bars and braces follow what they are over', () {
    final x = set('x'), wide = set('xyz');
    expect(set(r'\hat{x}').height, greaterThan(x.height));
    expect(set(r'\hat{x}').width, moreOrLessEquals(x.width, epsilon: 0.01));
    expect(set(r'\overline{xyz}').width, moreOrLessEquals(wide.width, epsilon: 0.01));
    expect(set(r'\underline{xyz}').depth, greaterThan(wide.depth));
    final brace = set(r'\underbrace{a+b+c+d}_{n}', display: true);
    expect(brace.width, moreOrLessEquals(set('a+b+c+d').width, epsilon: 0.01));
    expect(brace.depth, greaterThan(set(r'\underbrace{a+b+c+d}', display: true).depth));
    expect(set(r'A \xrightarrow{\text{une longue raison}} B').width, greaterThan(set(r'A \xrightarrow{f} B').width + 40));
  });

  test('nothing written makes the layout fail', () {
    const pieces = [
      'x', '1', '+', '=', '^', '_', "'", '{', '}', '[', ']', '(', ')', '|', '&', r'\\', '.', ' ', r'\', '%', '~', 'é', '你',
      r'\frac', r'\sqrt', r'\left', r'\right', r'\middle', r'\sum', r'\int', r'\hat', r'\widehat', r'\text{a b}',
      r'\over', r'\choose', r'\not', r'\big', r'\Biggl', r'\color{red}', r'\textcolor{#0af}', r'\displaystyle',
      r'\scriptscriptstyle', r'\limits', r'\nolimits', r'\xrightarrow', r'\underbrace', r'\overbrace', r'\overline',
      r'\begin{pmatrix}', r'\end{pmatrix}', r'\begin{cases}', r'\end{cases}', r'\begin{aligned}', r'\end{aligned}',
      r'\begin{array}{lr}', r'\end{array}', r'\begin{smallmatrix}', r'\substack', r'\operatorname', r'\binom',
      r'\phantom', r'\boxed', r'\mathbb', r'\mathcal', r'\bf', r'\lim', r'\sin', r'\quad', r'\hspace{1em}', r'\pmod',
      r'\stackrel', r'\overset', r'\underset', r'\inconnu', r'\langle', r'\|', r'\{', r'\}', r'\vec', r'\dots', r'\prime',
    ];
    final random = Random(7);
    for (var k = 0; k < 3000; k++) {
      final tex = [for (var n = random.nextInt(14) + 1; n > 0; n--) pieces[random.nextInt(pieces.length)]].join(' ');
      final f = set(tex, display: k.isEven);
      expect(f.width.isFinite && f.height.isFinite && f.depth.isFinite, isTrue, reason: tex);
      expect(f.width, greaterThanOrEqualTo(0), reason: tex);
    }
  });
}
