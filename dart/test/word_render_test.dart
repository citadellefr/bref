import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bref/src/ot/tree.dart';
import 'package:bref/src/word/blocks.dart';
import 'package:bref/src/word/document.dart';
import 'package:bref/src/word/layout.dart';
import 'package:bref/src/word/page_painter.dart';
import 'package:bref/src/word/paragraph.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fonts.dart';

/// Draws the pages of the trees in $BREF_WORD, as the Go package docx dumps
/// them, into PNG files beside them, with the fonts found in $BREF_FONTS:
/// a look at the rendering, not a test.
void main() {
  final dir = Platform.environment['BREF_WORD'];
  test('renders pages', () async {
    await loadFonts();
    for (final file in Directory(dir!).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      final base = file.path.substring(0, file.path.length - 5);
      final doc = WordDocument(Tree.fromEdit(Edit.fromJson(jsonDecode(file.readAsStringSync()))!)!);
      final images = <String, ui.Image>{};
      final media = Directory(base);
      if (media.existsSync()) {
        for (final m in media.listSync().whereType<File>()) {
          try {
            final codec = await ui.instantiateImageCodec(m.readAsBytesSync());
            images[m.uri.pathSegments.last] = (await codec.getNextFrame()).image;
          } on Object {
            // a format the engine does not read
          }
        }
      }
      final watch = Stopwatch()..start();
      final layout = WordLayout(doc, WordContext(doc), ParaCache());
      // ignore: avoid_print
      print('${file.path}: ${layout.pages.length} pages in ${watch.elapsedMilliseconds} ms');
      final painter = PagePainter(images: (m) => images[m]);
      for (final page in layout.pages.take(int.tryParse(Platform.environment['BREF_PAGES'] ?? '') ?? 6)) {
        const scale = 1.5;
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder)..scale(scale), page);
        final size = page.size * scale;
        final image = await recorder.endRecording().toImage(size.width.ceil(), size.height.ceil());
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$base-${page.index + 1}.png').writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  }, skip: dir == null ? 'BREF_WORD not set' : false);
}
