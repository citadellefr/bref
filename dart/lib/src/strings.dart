/// What the editor says besides the note; the app translates by overriding
/// what it shows.
class BrefStrings {
  const BrefStrings();

  String get cancel => 'Cancel';
  String get ask => 'Ask';
  String get askHint => 'The answer takes the place of the question';
  String get writeQuestion => 'Write your question, then Enter';
  String get thinking => 'Thinking…';
  String get noResult => 'No result';
  String get searchFailed => 'The search failed';
  String searchIn(String keyword) => 'Search in $keyword…';
  String questionFor(String keyword) => 'Your question for $keyword…';
}
