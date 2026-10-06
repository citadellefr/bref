import 'package:flutter/material.dart';
import 'package:trame/trame.dart';

import 'history.dart';
import 'host.dart';
import 'note_text.dart';
import 'strings.dart';

/// The earlier versions of a note beside it: pick one to see what restoring
/// it would change, and restore it as an edit like any other.
class HistoryPane extends StatefulWidget {
  const HistoryPane({super.key, required this.session, required this.host, this.strings = const BrefStrings(), this.onClose});

  final DocSession session;
  final BrefHost host;
  final BrefStrings strings;

  /// Shows a close button when given.
  final VoidCallback? onClose;

  @override
  State<HistoryPane> createState() => _HistoryPaneState();
}

class _HistoryPaneState extends State<HistoryPane> {
  List<NoteVersion>? _versions;
  Object? _failure;
  NoteVersion? _picked;
  String? _text;
  Object? _readFailure;

  BrefStrings get _s => widget.strings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failure = null);
    try {
      final versions = await widget.host.versions();
      if (mounted) setState(() => _versions = versions);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _pick(NoteVersion version) async {
    setState(() {
      _picked = version;
      _text = null;
      _readFailure = null;
    });
    try {
      final text = await widget.host.version(version.id);
      if (mounted && _picked == version) setState(() => _text = text);
    } on Object catch (error) {
      if (mounted && _picked == version) setState(() => _readFailure = error);
    }
  }

  void _restore() {
    final text = _text;
    if (text == null) return;
    widget.session.restoreText(text);
    setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(children: [
              if (_picked != null)
                IconButton(iconSize: 18, tooltip: _s.close, onPressed: () => setState(() => _picked = null), icon: const Icon(Icons.arrow_back)),
              Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_picked == null ? _s.history : _s.date(_picked!.at), style: theme.textTheme.titleSmall)),
              if (widget.onClose != null) IconButton(tooltip: _s.close, iconSize: 18, onPressed: widget.onClose, icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: _picked == null ? _list(theme) : _preview(theme)),
        ],
      ),
    );
  }

  Widget _message(ThemeData theme, String text, {VoidCallback? retry}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        if (retry != null) TextButton(onPressed: retry, child: Text(_s.retry)),
      ]),
    ),
  );

  Widget _list(ThemeData theme) {
    if (_failure != null) return _message(theme, '$_failure', retry: _load);
    final versions = _versions;
    if (versions == null) return const Center(child: CircularProgressIndicator());
    if (versions.isEmpty) return _message(theme, _s.noVersions);
    return ListView.builder(
      itemCount: versions.length,
      itemBuilder: (context, i) {
        final v = versions[i];
        return ListTile(
          dense: true,
          title: Text(_s.date(v.at)),
          subtitle: v.authors.isEmpty ? null : Text(v.authors.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _pick(v),
        );
      },
    );
  }

  Widget _preview(ThemeData theme) {
    if (_readFailure != null) return _message(theme, '$_readFailure', retry: () => _pick(_picked!));
    final text = _text;
    if (text == null) return const Center(child: CircularProgressIndicator());
    final now = widget.session.document[noteBody]?.text?.text ?? '\n';
    final diff = lineDiff(now.substring(0, now.length - 1).split('\n'), flowOf(text).substring(0, flowOf(text).length - 1).split('\n'));
    final changed = diff.any((l) => l.kind != DiffKind.same);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: !changed
            ? _message(theme, _s.noChanges)
            : ListView(padding: const EdgeInsets.all(8), children: [for (final l in _context(diff)) _line(theme, l)]),
      ),
      if (changed && !widget.session.readOnly)
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(onPressed: _restore, icon: const Icon(Icons.restore, size: 18), label: Text(_s.restore)),
        ),
    ]);
  }

  /// The changes with two lines around each; the rest is left out.
  static List<DiffLine?> _context(List<DiffLine> diff) {
    final keep = List<bool>.filled(diff.length, false);
    for (var i = 0; i < diff.length; i++) {
      if (diff[i].kind == DiffKind.same) continue;
      for (var k = i - 2; k <= i + 2; k++) {
        if (k >= 0 && k < diff.length) keep[k] = true;
      }
    }
    final out = <DiffLine?>[];
    for (var i = 0; i < diff.length; i++) {
      if (keep[i]) {
        out.add(diff[i]);
      } else if (out.isNotEmpty && out.last != null) {
        out.add(null);
      }
    }
    return out;
  }

  Widget _line(ThemeData theme, DiffLine? line) {
    if (line == null) return Text('…', style: theme.textTheme.bodySmall);
    final (color, mark) = switch (line.kind) {
      DiffKind.added => (Colors.green.withValues(alpha: 0.2), '+'),
      DiffKind.removed => (Colors.red.withValues(alpha: 0.2), '−'),
      DiffKind.same => (Colors.transparent, ' '),
    };
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Text('$mark ${line.text}', style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
    );
  }
}
