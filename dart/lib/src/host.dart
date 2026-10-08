import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// What a trigger proposes for the text typed after it, empty at first.
typedef MentionSource = Future<List<Mention>> Function(String query);

/// Someone or something to mention, written `[text](uri)`.
@immutable
class Mention {
  const Mention(this.text, this.uri, {this.detail, this.icon});

  /// What the link reads as: `@Alice`, `report.pdf`.
  final String text;
  final Uri uri;

  /// What the menu shows under the text: an address, a folder.
  final String? detail;

  /// What the menu shows before the text: an avatar, the icon of a file.
  final Widget? icon;
}

/// What a keyword that answers says on its way: what it is doing, then —
/// once, last — the text that takes the place of the question.
@immutable
class Answer {
  const Answer.step(this.text) : done = false;
  const Answer.done(this.text) : done = true;

  final String text;
  final bool done;
}

/// Answers a question written in the note, which [before] and [after] are
/// the text around. Giving up on the stream gives up on the answer.
typedef Answerer = Stream<Answer> Function(String question, {required String before, required String after});

/// A keyword of the host, written after an `@`: `@tasks` searches what to
/// mention, `@assistant` answers what is written after it on the line.
@immutable
class Command {
  const Command(this.keyword, {this.icon, this.search, this.answer});

  /// As it is proposed and written: one word, typed on any keyboard.
  final String keyword;
  final IconData? icon;

  /// What the keyword proposes for the text typed after it, empty at first.
  final MentionSource? search;

  /// Set on a keyword that writes instead of finding.
  final Answerer? answer;
}

/// How a link is shown in place of its text, as the host knows it now: the
/// name a person goes by, that of a file.
@immutable
class LinkLabel {
  const LinkLabel(this.text, {this.icon});

  final String text;
  final IconData? icon;
}

/// What the app hosting the editor provides: who and what can be mentioned,
/// where pictures go, what links stand for and how they open. Each member
/// has a default, which a host overrides with what it has.
abstract class BrefHost {
  const BrefHost();

  /// What typing each trigger, such as `@` or `[[`, proposes.
  Map<String, MentionSource> get mentions => const {};

  /// The keywords `@` starts, proposed beside what it mentions. A source
  /// or an answer that fails throws, after telling the person why.
  List<Command> get commands => const [];

  /// The schemes of the URIs the host makes, such as `user` or `file`:
  /// links lead to those, to relative ones and to those of the web, never
  /// elsewhere.
  Set<String> get schemes => const {};

  /// Keeps a picture and answers the URI to write in `![](…)`. It throws
  /// when it fails, after telling the person why.
  Future<Uri> upload(Uint8List bytes, String name, String type) => throw UnsupportedError('No upload');

  /// The picture behind [uri], or null to show its description: remote
  /// pictures are the host's call, as they tell their server who reads.
  ImageProvider? image(Uri uri) => null;

  /// How the link to [uri] is shown, or null to show it as written.
  Future<LinkLabel?> describe(Uri uri) async => null;

  void open(Uri uri) {}
}

const _web = {'http', 'https', 'mailto', 'tel'};

/// The URI of a wiki link: the path of the note it names.
Uri wikiUri(String dest) {
  final hash = dest.indexOf('#');
  return hash < 0 ? Uri(path: dest) : Uri(path: dest.substring(0, hash), fragment: dest.substring(hash + 1));
}

/// The URI a link leads to, or null when it leads nowhere [host] goes.
Uri? linkUri(BrefHost host, String dest, {required bool wiki}) {
  if (wiki) return wikiUri(dest);
  final uri = Uri.tryParse(dest);
  if (uri == null || uri.hasScheme && !_web.contains(uri.scheme) && !host.schemes.contains(uri.scheme)) return null;
  return uri;
}
