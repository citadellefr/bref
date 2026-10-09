import 'package:flutter/widgets.dart';

import 'host.dart';

/// What the host answered for the links of a note: the pictures behind
/// them, loaded, and how they are shown. Each is asked once; [onChanged] is
/// told of the links whose answer arrived later, [onFrame] of a picture
/// that moved on to its next frame.
class HostCache {
  HostCache(this.host, {required this.onChanged, required this.onFrame});

  final BrefHost host;
  final ValueChanged<String> onChanged;
  final VoidCallback onFrame;
  ImageConfiguration configuration = ImageConfiguration.empty;

  final _pictures = <String, _Picture>{};
  final _labels = <String, LinkLabel?>{};
  var _disposed = false;

  /// The picture [dest] leads to, once it is loaded.
  ImageInfo? picture(String dest) {
    final known = _pictures[dest];
    if (known != null) return known.info;
    final picture = _pictures[dest] = _Picture();
    final uri = linkUri(host, dest, wiki: false);
    final provider = uri == null ? null : host.image(uri);
    if (provider == null) return null;
    final stream = provider.resolve(configuration);
    var sync = true;
    final listener = ImageStreamListener(
      (info, _) {
        final first = picture.info == null;
        picture.info?.dispose();
        picture.info = info;
        if (sync || _disposed) return;
        first ? onChanged(dest) : onFrame();
      },
      onError: (_, _) {},
    );
    picture
      ..stream = stream
      ..listener = listener;
    stream.addListener(listener);
    sync = false;
    return picture.info;
  }

  /// How the link to [dest] is shown, once the host said it.
  LinkLabel? label(String dest) {
    if (_labels.containsKey(dest)) return _labels[dest];
    _labels[dest] = null;
    final uri = linkUri(host, dest, wiki: false);
    if (uri == null) return null;
    host.describe(uri).then(
      (label) {
        if (_disposed || label == null) return;
        _labels[dest] = label;
        onChanged(dest);
      },
      onError: (Object _) {},
    );
    return null;
  }

  void dispose() {
    _disposed = true;
    for (final p in _pictures.values) {
      if (p.listener case final listener?) p.stream?.removeListener(listener);
      p.info?.dispose();
    }
    _pictures.clear();
  }
}

class _Picture {
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;
}
