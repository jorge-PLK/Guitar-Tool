import 'dart:io';

import 'package:flutter/painting.dart';

/// `FileImage` cuya clave de caché incluye la `version` del fotograma: el núcleo reescribe
/// siempre el mismo fichero y solo `version` distingue un fotograma de otro.
class VersionedFileImage extends FileImage {
  const VersionedFileImage(super.file, {required this.version});

  final int version;

  @override
  bool operator ==(Object other) =>
      other is VersionedFileImage && other.file.path == file.path && other.scale == scale && other.version == version;

  @override
  int get hashCode => Object.hash(file.path, scale, version);
}

/// Proveedor del fotograma de [path] en la versión [version].
VersionedFileImage framingFrameImage(String path, int version) => VersionedFileImage(File(path), version: version);
