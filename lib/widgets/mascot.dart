import 'package:flutter/material.dart';

/// The recurring mic-with-face mascot (D-13/D-14).
///
/// Composed entirely from Flutter primitives — no bundled image asset and no
/// network fetch — so it renders identically wherever it is placed, including
/// inside a bare `MaterialApp` in tests. The three UI-SPEC tokens it needs are
/// therefore written literally here rather than read from the ambient theme.
///
/// Tone contract: the face is always friendly. The [isError] variant reads as
/// *concerned*, never sad, frowning, disappointed, or mocking — this app has no
/// scoring and must never appear to judge the user's answer.
class Mascot extends StatefulWidget {
  const Mascot({super.key, this.isRecording = false, this.isError = false});

  /// Listening face + the accent pulse ring, shown only while actively
  /// recording.
  final bool isRecording;

  /// Concerned (not sad) face, paired with the error-state copy.
  final bool isError;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  /// Secondary (30%) — the mascot's peach body.
  static const Color _body = Color(0xFFFFDDB3);

  /// Text-on-color — the warm brown face features.
  static const Color _face = Color(0xFF3D2B1F);

  /// Accent (10%) — the recording pulse ring. Marks something actively
  /// happening, which is exactly what the accent is reserved for.
  static const Color _accent = Color(0xFFFF6B35);

  /// Visual anchor size from the UI-SPEC spacing exceptions (not a tap target).
  static const double _diameter = 120;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Constructed eagerly, never in a field initialiser: a lazy `late final`
    // would be created for the first time inside dispose() when the mascot was
    // never in the recording state, and creating a Ticker while the element is
    // deactivating throws.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isRecording) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant Mascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording == oldWidget.isRecording) return;
    if (widget.isRecording) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.isRecording ? 'Listening' : 'EnglishReflex mascot',
      child: SizedBox(
        // Leaves room for the ring at its largest pulse (120 * 1.15 = 138).
        width: 144,
        height: 144,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.isRecording) _buildPulseRing(),
              _buildFace(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPulseRing() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.scale(
          scale: 1 + 0.15 * t,
          child: Opacity(opacity: 1 - 0.5 * t, child: child),
        );
      },
      child: Container(
        key: const Key('mascot-pulse-ring'),
        width: _diameter,
        height: _diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _accent, width: 4),
        ),
      ),
    );
  }

  Widget _buildFace() {
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _body, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 28,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildEye(mirrored: false),
                  const SizedBox(width: 22), // sm-ish gap between the eyes
                  _buildEye(mirrored: true),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Icon(Icons.mic_rounded, size: 56, color: _face),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEye({required bool mirrored}) {
    if (widget.isError) {
      // Slightly angled dashes — an "oh, something went wrong" look. Angled
      // upward at the outer edge so it never reads as a frown aimed at the user.
      return Transform.rotate(
        angle: mirrored ? -0.35 : 0.35,
        child: Container(
          width: 16,
          height: 4,
          decoration: BoxDecoration(
            color: _face,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }
    // Listening = wide-open eyes; idle = smaller, resting eyes.
    final double size = widget.isRecording ? 12 : 8;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _face, shape: BoxShape.circle),
    );
  }
}
