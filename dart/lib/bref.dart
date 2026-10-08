/// Collaborative Markdown notes: the client of the Bref Go server.
library;

export 'package:trame/trame.dart' show DocSession;
export 'src/editor.dart' show BrefEditor, BrefEditorState, noteBody;
export 'src/host.dart' show Answer, Answerer, BrefHost, Command, LinkLabel, Mention, MentionSource;
export 'src/local.dart' show localNote, noteText;
export 'src/strings.dart' show BrefStrings;
export 'src/theme.dart' show BrefTheme;
