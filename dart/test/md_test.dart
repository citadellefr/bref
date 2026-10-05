import 'dart:convert';
import 'dart:io';

import 'package:bref/src/md/block.dart';
import 'package:bref/src/md/node.dart';
import 'package:flutter_test/flutter_test.dart';

const _dialects = {'commonmark': MdSyntax.commonMark, 'gfm': MdSyntax.gfm, 'bref': MdSyntax.bref};

String _snake(String name) => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

Map<String, Object?> dump(MdNode n) {
  List<int> span(Span s) => [s.start, s.end];
  final d = <String, Object?>{'k': _snake(n.kind.name), 's': n.start, 'e': n.end};
  if (n.marks.isNotEmpty) d['m'] = [for (final m in n.marks) span(m)];
  if (n.literal.isNotEmpty) d['lit'] = n.literal;
  if (n.level != 0) d['level'] = n.level;
  if (n.info.isNotEmpty) d['info'] = n.info;
  if (n.kind == MdKind.list) {
    d
      ..['ordered'] = n.ordered
      ..['number'] = n.number
      ..['tight'] = n.tight
      ..['marker'] = n.marker;
  }
  if (n.task != Task.none) d['task'] = n.task.index;
  if (n.kind == MdKind.table) d['align'] = [for (final a in n.align) a.index];
  if (n.header) d['header'] = true;
  if (n.kind == MdKind.link || n.kind == MdKind.image || n.kind == MdKind.definition) {
    d
      ..['dest'] = n.dest
      ..['title'] = n.title
      ..['form'] = n.form.index
      ..['url'] = span(n.url);
    if (n.label.isNotEmpty) d['label'] = n.label;
  }
  if (n.display) d['display'] = true;
  if (n.children.isNotEmpty) d['c'] = [for (final c in n.children) dump(c)];
  return d;
}

/// [v] with the keys of its maps sorted, as Go writes them.
Object? _canon(Object? v) => switch (v) {
      Map<String, Object?>() => {for (final k in v.keys.toList()..sort()) k: _canon(v[k])},
      List<Object?>() => [for (final e in v) _canon(e)],
      _ => v,
    };

void main() {
  test('finds the trees the Go parser finds', () {
    final vectors = jsonDecode(File('../testdata/md/vectors.json').readAsStringSync()) as List<Object?>;
    final failures = <String>[];
    for (final v in vectors.cast<Map<String, Object?>>()) {
      final md = v['md']! as String;
      final got = jsonEncode(_canon(dump(parseMarkdown(md, syntax: _dialects[v['dialect']]!))));
      final want = jsonEncode(_canon(v['tree']));
      if (got != want) failures.add('${v['dialect']} ${jsonEncode(md)}\n  got  $got\n  want $want');
    }
    expect(failures, isEmpty, reason: '${failures.length} of ${vectors.length}:\n${failures.take(8).join('\n')}');
  });
}
