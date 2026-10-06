import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'comments.dart';
import 'controller.dart';
import 'strings.dart';

/// The comments of a note beside it: a card by thread, in the order of the
/// text, answered, resolved, edited and deleted there, and the comment being
/// written.
class CommentsPane extends StatefulWidget {
  const CommentsPane({super.key, required this.comments, this.strings = const BrefStrings(), this.onClose});

  final BrefComments comments;
  final BrefStrings strings;

  /// Shows a close button when given.
  final VoidCallback? onClose;

  @override
  State<CommentsPane> createState() => _CommentsPaneState();
}

class _CommentsPaneState extends State<CommentsPane> {
  final _draft = TextEditingController();
  final _reply = TextEditingController();
  final _editing = TextEditingController();
  final _draftFocus = FocusNode();
  final _keys = <String, GlobalKey>{};
  String? _edited;
  String? _opened;
  var _drafting = false;

  BrefComments get _comments => widget.comments;

  BrefStrings get _s => widget.strings;

  bool get _editable => !_comments.session.readOnly;

  @override
  void initState() {
    super.initState();
    _comments.addListener(_changed);
    _opened = _comments.selected;
    _drafting = _comments.draft != null;
    if (_drafting) _draftFocus.requestFocus();
  }

  @override
  void didUpdateWidget(CommentsPane old) {
    super.didUpdateWidget(old);
    if (old.comments != _comments) {
      old.comments.removeListener(_changed);
      _comments.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _comments.removeListener(_changed);
    _draft.dispose();
    _reply.dispose();
    _editing.dispose();
    _draftFocus.dispose();
    super.dispose();
  }

  void _changed() {
    final drafting = _comments.draft != null;
    if (drafting && !_drafting) {
      _draft.clear();
      _draftFocus.requestFocus();
    }
    _drafting = drafting;
    if (_comments.selected != _opened) {
      _opened = _comments.selected;
      _reply.clear();
      final key = _keys[_opened];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = key?.currentContext;
        if (context != null && context.mounted) {
          Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 200), alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        }
      });
    }
    setState(() {});
  }

  void _post() {
    final text = _draft.text.trim();
    if (text.isNotEmpty && _comments.post(text)) _draft.clear();
  }

  void _sendReply(CommentThread thread) {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    if (_comments.session.reply(thread.id, text)) _reply.clear();
  }

  void _saveEditing(CommentMessage m) {
    final text = _editing.text.trim();
    if (text.isNotEmpty && text != m.text) _comments.session.editMessage(m.id, text);
    setState(() => _edited = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final threads = _comments.threads;
    final drafting = _comments.draft != null;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(children: [
              Icon(Icons.forum_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(_s.comments, style: theme.textTheme.titleSmall)),
              if (threads.isNotEmpty) Text('${threads.length}', style: theme.textTheme.labelMedium),
              Tooltip(
                message: _s.authorship,
                child: IconButton(
                  isSelected: _comments.authorship,
                  iconSize: 18,
                  onPressed: () => _comments.authorship = !_comments.authorship,
                  icon: const Icon(Icons.format_color_text),
                ),
              ),
              if (widget.onClose != null) IconButton(tooltip: _s.close, iconSize: 18, onPressed: widget.onClose, icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: threads.isEmpty && !drafting
                ? _empty(theme)
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (drafting) _draftCard(theme),
                      for (final t in threads) _threadCard(theme, t),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline, size: 36, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(_s.noComments, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (_editable) Text(_s.noCommentsHint, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ]),
    ),
  );

  Widget _card(ThemeData theme, {required bool active, required Widget child, VoidCallback? onTap, Key? key, bool dim = false}) {
    final scheme = theme.colorScheme;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dim ? 0.7 : 1,
        child: Material(
          color: scheme.surface,
          elevation: active ? 3 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: active ? scheme.primary : scheme.outlineVariant, width: active ? 1.5 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(12), child: child)),
        ),
      ),
    );
  }

  Widget _draftCard(ThemeData theme) => _card(
    theme,
    active: true,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(theme, _comments.session.name, null),
      const SizedBox(height: 8),
      _field(_draft, _s.startConversation, focus: _draftFocus, submit: _post, cancel: _comments.cancelDraft),
      const SizedBox(height: 8),
      OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
        TextButton(onPressed: _comments.cancelDraft, child: Text(_s.cancel)),
        ListenableBuilder(
          listenable: _draft,
          builder: (context, _) => FilledButton.icon(
            onPressed: _draft.text.trim().isEmpty ? null : _post,
            icon: const Icon(Icons.send, size: 16),
            label: Text(_s.post),
          ),
        ),
      ]),
    ]),
  );

  Widget _threadCard(ThemeData theme, CommentThread t) {
    final active = t.id == _comments.selected;
    final collapsed = t.done && !active;
    final replies = t.messages.skip(1).toList();
    return _card(
      theme,
      key: _keys.putIfAbsent(t.id, GlobalKey.new),
      active: active,
      dim: t.done,
      onTap: () => _comments.select(t.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t.messages.isNotEmpty) _message(theme, t.messages.first, t, first: true, collapsed: collapsed),
        if (!collapsed)
          for (final r in replies) ...[
            const SizedBox(height: 10),
            _message(theme, r, t, first: false, collapsed: false),
          ],
        if (collapsed && replies.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_s.replies(replies.length), style: theme.textTheme.labelSmall)),
        if (t.orphan)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_s.commentedTextGone, style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.outline)),
          ),
        if (active && _editable && !t.done) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(_reply, _s.replyHint, submit: () => _sendReply(t))),
            ListenableBuilder(
              listenable: _reply,
              builder: (context, _) => IconButton(
                tooltip: _s.post,
                onPressed: _reply.text.trim().isEmpty ? null : () => _sendReply(t),
                icon: const Icon(Icons.send, size: 18),
              ),
            ),
          ]),
        ],
        if (active && _editable && t.done)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _comments.session.resolve(t.id, done: false),
              icon: const Icon(Icons.replay, size: 16),
              label: Text(_s.reopen),
            ),
          ),
      ]),
    );
  }

  Widget _message(ThemeData theme, CommentMessage m, CommentThread t, {required bool first, required bool collapsed}) {
    final session = _comments.session;
    final mine = m.by == session.id;
    final text = _edited == m.id
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field(_editing, '', autofocus: true, submit: () => _saveEditing(m), cancel: () => setState(() => _edited = null)),
            OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
              TextButton(onPressed: () => setState(() => _edited = null), child: Text(_s.cancel)),
              FilledButton(onPressed: () => _saveEditing(m), child: Text(_s.save)),
            ]),
          ])
        : Text(m.text, maxLines: collapsed ? 1 : null, overflow: collapsed ? TextOverflow.ellipsis : null, style: theme.textTheme.bodyMedium);
    final owner = t.messages.every((x) => x.by == session.id);
    final items = [
      if (_editable && mine) PopupMenuItem(value: 'edit', child: Text(_s.editComment)),
      if (_editable && first) PopupMenuItem(value: 'resolve', child: Text(t.done ? _s.reopen : _s.resolveThread)),
      if (_editable && mine && (!first || owner)) PopupMenuItem(value: 'delete', child: Text(first ? _s.deleteThread : _s.deleteComment)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _header(theme, m.name, m.at, small: !first)),
        if (first && t.done)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(label: Text(_s.resolved), visualDensity: VisualDensity.compact, labelStyle: theme.textTheme.labelSmall),
          ),
        if (items.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: _s.moreActions,
            iconSize: 18,
            icon: const Icon(Icons.more_horiz),
            itemBuilder: (context) => items,
            onSelected: (v) => switch (v) {
              'edit' => setState(() {
                _edited = m.id;
                _editing.text = m.text;
              }),
              'resolve' => session.resolve(t.id, done: !t.done),
              _ => first ? session.deleteThread(t.id) : session.deleteMessage(m.id),
            },
          ),
      ]),
      const SizedBox(height: 4),
      text,
    ]);
  }

  Widget _header(ThemeData theme, String name, DateTime? date, {bool small = false}) {
    final color = theme.colorScheme.primary;
    final initials = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Row(children: [
      CircleAvatar(
        radius: small ? 11 : 14,
        backgroundColor: color,
        child: Text(initials, style: TextStyle(fontSize: small ? 9 : 11, color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? _s.unknownAuthor : name, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge),
          if (date != null) Text(_s.date(date), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        ]),
      ),
    ]);
  }

  Widget _field(TextEditingController c, String hint, {FocusNode? focus, bool autofocus = false, required VoidCallback submit, VoidCallback? cancel}) =>
      CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
          const SingleActivator(LogicalKeyboardKey.escape): ?cancel,
        },
        child: TextField(
          controller: c,
          focusNode: focus,
          autofocus: autofocus,
          minLines: 1,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.all(8)),
        ),
      );
}
