/// What the editor says besides the note; the app translates by overriding
/// what it shows.
class BrefStrings {
  const BrefStrings();

  String get comments => 'Comments';
  String get comment => 'Comment';
  String get noComments => 'No comments';
  String get noCommentsHint => 'Select a passage and choose Comment.';
  String get startConversation => 'Write a comment';
  String get replyHint => 'Reply';
  String get post => 'Post';
  String get cancel => 'Cancel';
  String get save => 'Save';
  String get close => 'Close';
  String get resolved => 'Resolved';
  String get reopen => 'Reopen';
  String get resolveThread => 'Resolve';
  String get editComment => 'Edit';
  String get deleteComment => 'Delete comment';
  String get deleteThread => 'Delete thread';
  String get moreActions => 'More';
  String get commentedTextGone => 'The commented text was deleted.';
  String get unknownAuthor => 'Someone';
  String get authorship => 'Who wrote what';
  String get history => 'History';
  String get noVersions => 'No earlier versions';
  String get restore => 'Restore this version';
  String get noChanges => 'Same as the note now';
  String get unreadable => 'The version could not be read';
  String get retry => 'Retry';
  String replies(int n) => n == 1 ? '1 reply' : '$n replies';
  String date(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}
