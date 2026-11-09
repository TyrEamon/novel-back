import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// One page face as a triangle mesh. A grid is what lets the curl bend the
/// printed page instead of shearing a flat picture: `normals` carries one facing
/// value per vertex (1 facing the reader, 0 edge on) and drives the shading the
/// painter applies to both the paper and its ink.
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

/// The roll at the crease for one row of the page.
class _Roll {
  const _Roll({
    required this.radius,
    required this.flat,
    required this.angle,
    required this.edge,
  });

  /// Radius of the rolled band. Zero leaves the row perfectly flat, which is how
  /// the first and last frames stay gapless.
  final double radius;

  /// Length of the row that is still lying flat, measured from the spine.
  final double flat;

  /// How far the sheet has wrapped, in radians, before it drops behind itself.
  final double angle;

  /// Where the rolled band ends, i.e. the visible leading edge of the paper.
  final double edge;
}

/// Geometry for the paper turn, in the canonical frame the painter uses: the
/// spine sits at x = 0 and the free edge at x = w, so a right-to-left turn walks
/// the crease from the free edge back to the spine as `progress` runs 0 -> 1.
///
/// The crease is a rolled band rather than a straight line: the sheet leaves the
/// flat page, wraps a quarter turn and continues behind itself as the underside.
/// `touchY` (0..1, the finger's row) decides where the roll stays tight; rows
/// away from it keep more of the page flat, which is what turns a hinge into a
/// swept spine.
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

  /// Normalised row of the finger: 0 at the top of the page, 1 at the bottom.
  final double touchY;

  static const int _rows = 14;
  static const int _flatColumns = 10;
  static const int _rollColumns = 12;
  static const int _undersideColumns = 5;

  ReaderPaperMesh? _front;
  ReaderPaperMesh? _back;

  double get _t => progress.clamp(0.0, 1.0);
  double get _envelope => math.sin(_t * math.pi);
  double get _w => math.max(1.0, size.width);
  double get _h => math.max(1.0, size.height);

  /// Rows further from the finger lift later, so the leading edge is a slanted
  /// roll. Kept at 1 near the finger so the sheet never pulls away from it.
  double _taper(double y) =>
      1 - .72 * (y / _h - touchY).abs().clamp(0.0, 1.0);

  _Roll _roll(double y) {
    final taper = _taper(y);
    // The sheet gathers into the roll quickly, so the region it has left behind
    // (everything to the left of the band) is already the next page past the
    // middle of the turn. A narrow roll kept the outgoing text on screen for
    // most of the gesture, which reads as the pages barely moving.
    final radius =
        math.min(.34 * _w, 120.0) *
        math.pow(_envelope, .6).toDouble() *
        taper;
    // The lag is what sweeps the spine: without it every row would fold on the
    // same vertical line and the turn would read as a hinge.
    final lead = .09 * _w * _envelope * (1 - taper);
    final crease = (_w * (1 - _t) + lead).clamp(0.0, _w);
    final flat = math.max(0.0, crease - radius);
    final angle = (math.pi / 2) * _envelope;
    return _Roll(
      radius: radius,
      flat: flat,
      angle: angle,
      edge: flat + radius * math.sin(angle),
    );
  }

  /// How far the paper stands off the page. The painter turns this into the
  /// cast shadow along the leading edge, so it rises and falls with the turn.
  double get lift => _envelope;

  /// The footprint the moving sheet hides, used to occlude the page below.
  Path get sheet => back.outline;

  ReaderPaperMesh get front => _front ??= _frontFace();

  ReaderPaperMesh get back => _back ??= _underside();

  ReaderPaperMesh get frontInk => front;

  ReaderPaperMesh get backInk => back;

  Float32List _positions(int columns, int rows) =>
      Float32List(columns * rows * 2);

  ReaderPaperMesh _frontFace() {
    final rows = _rows + 1;
    final columns = _flatColumns + _rollColumns + 1;
    final positions = _positions(columns, rows);
    final normals = Float32List(columns * rows);
    final uv = Float32List(columns * rows * 2);
    final indices = Uint16List((rows - 1) * (columns - 1) * 6);
    final roll = <_Roll>[];

    for (var r = 0; r < rows; r++) {
      final y = _h * r / _rows;
      final current = _roll(y);
      roll.add(current);
      for (var c = 0; c < columns; c++) {
        // Columns are spent on arc length, not screen distance: the flat part
        // gets a fixed count and the roll gets the rest, so the bend stays smooth
        // however wide the roll happens to be this frame.
        final along = c <= _flatColumns
            ? current.flat * c / _flatColumns
            : current.flat +
                  current.radius *
                      current.angle *
                      (c - _flatColumns) /
                      _rollColumns;
        final wrapped = c > _flatColumns && current.radius > 0;
        final phi = wrapped ? (along - current.flat) / current.radius : 0.0;
        final i = r * columns + c;
        positions[i * 2] = wrapped
            ? current.flat + current.radius * math.sin(phi)
            : along;
        positions[i * 2 + 1] = y;
        normals[i] = wrapped ? math.cos(phi) : 1;
        uv[i * 2] = (along / _w).clamp(0.0, 1.0);
        uv[i * 2 + 1] = (_h <= 0 ? 0.0 : y / _h).clamp(0.0, 1.0);
      }
    }

    var index = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < columns - 1; c++) {
        final tl = r * columns + c, tr = tl + 1;
        final bl = tl + columns, br = bl + 1;
        indices[index++] = tl;
        indices[index++] = tr;
        indices[index++] = bl;
        indices[index++] = tr;
        indices[index++] = br;
        indices[index++] = bl;
      }
    }

    // The visible face is everything from the spine to the rolled edge.
    final outline = Path()..moveTo(0, 0);
    for (var r = 0; r < rows; r++) {
      outline.lineTo(math.min(_w, roll[r].edge), _h * r / _rows);
    }
    outline
      ..lineTo(0, _h)
      ..close();

    return ReaderPaperMesh(
      positions: positions,
      indices: indices,
      normals: normals,
      uv: uv,
      outline: outline,
    );
  }

  /// The strip of paper that has already wrapped past the crease. It hangs
  /// behind the roll, so its facing value climbs from edge on at the crease back
  /// to flat once it has come round.
  ReaderPaperMesh _underside() {
    final rows = _rows + 1;
    final columns = _undersideColumns + 1;
    final positions = _positions(columns, rows);
    final normals = Float32List(columns * rows);
    final uv = Float32List(columns * rows * 2);
    final indices = Uint16List((rows - 1) * (columns - 1) * 6);
    final left = Float64List(rows);
    final right = Float64List(rows);

    for (var r = 0; r < rows; r++) {
      final y = _h * r / _rows;
      final current = _roll(y);
      // A turn past the crease covers roughly the rolled arc as seen from the
      // front, foreshortened by the angle it has come round.
      final span = current.radius * math.sin(current.angle);
      right[r] = current.edge;
      left[r] = current.edge - span;
      for (var c = 0; c < columns; c++) {
        final f = c / _undersideColumns;
        final i = r * columns + c;
        positions[i * 2] = right[r] - span * (1 - f);
        positions[i * 2 + 1] = y;
        // Facing runs from edge on where the sheet leaves the roll to almost
        // flat where the far side has come round.
        normals[i] = .15 + .8 * f * current.angle / (math.pi / 2);
        uv[i * 2] = (positions[i * 2] / _w).clamp(0.0, 1.0);
        uv[i * 2 + 1] = (_h <= 0 ? 0.0 : y / _h).clamp(0.0, 1.0);
      }
    }

    var index = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < columns - 1; c++) {
        final tl = r * columns + c, tr = tl + 1;
        final bl = tl + columns, br = bl + 1;
        indices[index++] = tl;
        indices[index++] = tr;
        indices[index++] = bl;
        indices[index++] = tr;
        indices[index++] = br;
        indices[index++] = bl;
      }
    }

    final outline = Path()..moveTo(left[0], 0);
    for (var r = 0; r < rows; r++) {
      outline.lineTo(right[r], _h * r / _rows);
    }
    for (var r = rows - 1; r >= 0; r--) {
      outline.lineTo(left[r], _h * r / _rows);
    }
    outline.close();

    return ReaderPaperMesh(
      positions: positions,
      indices: indices,
      normals: normals,
      uv: uv,
      outline: outline,
    );
  }
}
