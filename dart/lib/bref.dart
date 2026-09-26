/// Collaborative Office documents: the client of the Bref Go server.
library;

export 'src/chrome/strings.dart' show BrefStrings;
export 'src/ot/delta.dart' show Attributes, Delta, Op;
export 'src/ot/tree.dart' show Change, ChangeKind, Edit, Node, Tree, diffTrees, keyBetween;
export 'src/plain_text_editor.dart' show PlainTextEditor;
export 'src/powerpoint/editor.dart' show PresentationEditor;
export 'src/powerpoint/slide_painter.dart' show MediaFetcher;
export 'src/session.dart'
    show DocClosed, DocConnector, DocPeer, DocSelection, DocSession, DocStatus, DocTransport, randomId, webSocketConnector;
