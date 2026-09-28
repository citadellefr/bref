import 'dart:convert';
import 'dart:io';

import 'package:bref/src/ot/tree.dart';
import 'package:bref/src/word/blocks.dart';
import 'package:bref/src/word/document.dart';
import 'package:bref/src/word/edits.dart';
import 'package:bref/src/word/layout.dart';
import 'package:bref/src/word/paragraph.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lays out every tree of $BREF_WORD_CORPUS, as the Go package docx dumps
/// them, and puts a caret in each flow: none may throw.
void main() {
  final dir = Platform.environment['BREF_WORD_CORPUS'];
  test('lays out the corpus', skip: dir == null ? 'BREF_WORD_CORPUS not set' : false, () {
    var documents = 0, pages = 0;
    final failures = <String>[];
    final slow = <(int, String)>[];
    for (final file in Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final tree = Tree.fromEdit(Edit.fromJson(jsonDecode(file.readAsStringSync()))!);
      if (tree == null) {
        failures.add('${file.path}: no tree');
        continue;
      }
      try {
        final watch = Stopwatch()..start();
        final doc = WordDocument(tree);
        final layout = WordLayout(doc, WordContext(doc), ParaCache());
        slow.add((watch.elapsedMilliseconds, file.path));
        documents++;
        pages += layout.pages.length;
        for (final flow in flowsOf(tree)) {
          final caret = layout.caret(flow.id, 0);
          if (caret == null) continue;
          layout.hit(caret.$1, caret.$2.center);
          layout.selection(flow.id, 0, flow.text!.length);
        }
      } on Object catch (e, stack) {
        failures.add('${file.path}: $e\n${stack.toString().split('\n').take(6).join('\n')}');
      }
    }
    slow.sort((a, b) => b.$1.compareTo(a.$1));
    // ignore: avoid_print
    print('$documents documents, $pages pages; slowest: ${slow.take(5).map((s) => '${s.$2.split('/').last} ${s.$1} ms').join(', ')}');
    for (final f in failures.take(20)) {
      // ignore: avoid_print
      print(f);
    }
    expect(failures, isEmpty);
  });
}
