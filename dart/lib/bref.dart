/// Collaborative Markdown notes: the client of the Bref Go server.
library;

export 'src/comments.dart' show CommentMessage, CommentThread, Comments, readThreads;
export 'src/comments_pane.dart' show CommentsPane;
export 'src/controller.dart' show BrefComments, BrefFollow;
export 'src/editor.dart' show BrefEditor, BrefEditorState, noteBody;
export 'src/history.dart' show DiffKind, DiffLine, History, flowOf, lineDiff;
export 'src/history_pane.dart' show HistoryPane;
export 'src/host.dart' show BrefHost, LinkLabel, Mention, MentionSource, NoteVersion;
export 'src/strings.dart' show BrefStrings;
export 'src/theme.dart' show BrefTheme;
