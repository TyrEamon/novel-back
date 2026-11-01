import 'dart:typed_data';
import 'dart:ui';

/// One page face as a triangle mesh. The unpublished original curled the paper
/// with a swept spine; this placeholder stays flat, which keeps `lift` at zero.
class ReaderPaperMesh {
  const ReaderPaperMesh({
    required this.positions,
    required this.indices,
    required this.normals,
    required this.uv,
    required this.outline,
  });

  final Float32List positions;
  final Uint16List indices;
  final Float32List normals;
  final Float32List uv;
  final Path outline;
}

class ReaderPaperGeometry {
  ReaderPaperGeometry({
    required this.size,
    required this.gap,
    required this.progress,
    required this.touchY,
  });

  final Size size;
  final double gap;
  final double progress;
  final double touchY;

  double get lift => 0;

  Path get sheet => Path();

  ReaderPaperMesh get front => _flat(size);

  ReaderPaperMesh get back => _flat(size);

  ReaderPaperMesh get frontInk => _flat(size);

  ReaderPaperMesh get backInk => _flat(size);

  static ReaderPaperMesh _flat(Size size) {
    final w = size.width, h = size.height;
    return ReaderPaperMesh(
      positions: Float32List.fromList([0, 0, w, 0, w, h, 0, h]),
      indices: Uint16List.fromList([0, 1, 2, 0, 2, 3]),
      normals: Float32List.fromList([0, 0, 0, 0]),
      uv: Float32List.fromList([0, 0, 1, 0, 1, 1, 0, 1]),
      outline: Path()..addRect(Offset.zero & size),
    );
  }
}