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
  final _faces = <String, _Picture>{};
  final _labels = <String, LinkLabel?>{};
  var _disposed = false;

  /// The picture [dest] leads to, once it is loaded.
  ImageInfo? picture(String dest) => _load(_pictures, dest, () {
        final uri = linkUri(host, dest, wiki: false);
        return uri == null ? null : host.image(uri);
      }, () => onChanged(dest));

  /// The picture of the label of [dest], once it is loaded.
  ImageInfo? face(String dest) => _load(_faces, dest, () => _labels[dest]?.image, onFrame);

  ImageInfo? _load(Map<String, _Picture> kept, String dest, ImageProvider? Function() find, VoidCallback arrived) {
    final known = kept[dest];
    if (known != null) return known.info;
    final picture = kept[dest] = _Picture();
    final provider = find();
    if (provider == null) return null;
    final stream = provider.resolve(configuration);
    var sync = true;
    final listener = ImageStreamListener(
      (info, _) {
        final first = picture.info == null;
        picture.info?.dispose();
        picture.info = info;
        if (sync || _disposed) return;
        first ? arrived() : onFrame();
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
    for (final p in [..._pictures.values, ..._faces.values]) {
      if (p.listener case final listener?) p.stream?.removeListener(listener);
      p.info?.dispose();
    }
    _pictures.clear();
    _faces.clear();
  }
}

class _Picture {
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;
}
