import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class ScanCameraPreview extends StatelessWidget {
  const ScanCameraPreview({
    required this.camera,
    required this.imagePath,
    required this.isLoading,
    required this.error,
    required this.showGrid,
    required this.focusPoint,
    required this.onRetry,
    required this.onFocus,
    super.key,
  });

  final CameraController? camera;
  final String? imagePath;
  final bool isLoading;
  final String? error;
  final bool showGrid;
  final Offset? focusPoint;
  final VoidCallback onRetry;
  final ValueChanged<Offset> onFocus;

  @override
  Widget build(BuildContext context) {
    if (imagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.file(
          File(imagePath!),
          height: 340,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      );
    }

    if (isLoading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final currentCamera = camera;
    if (error != null ||
        currentCamera == null ||
        !currentCamera.value.isInitialized) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined,
                size: 44),
            const SizedBox(height: 12),
            Text(error ?? 'Camera is not ready.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 340);
          return SizedBox.fromSize(
            size: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                onFocus(
                  Offset(
                    (details.localPosition.dx / size.width)
                        .clamp(0.0, 1.0),
                    (details.localPosition.dy / size.height)
                        .clamp(0.0, 1.0),
                  ),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(currentCamera),
                  if (showGrid)
                    const IgnorePointer(
                      child: CustomPaint(
                          painter: _CameraGridPainter()),
                    ),
                  if (focusPoint case final point?)
                    Positioned(
                      left: point.dx * size.width - 18,
                      top: point.dy * size.height - 18,
                      child: const IgnorePointer(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.fromBorderSide(
                                BorderSide(
                                    color: Colors.white,
                                    width: 2),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CameraGridPainter extends CustomPainter {
  const _CameraGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .7)
      ..strokeWidth = 1;

    for (var index = 1; index <= 2; index++) {
      final dx = size.width * index / 3;
      final dy = size.height * index / 3;
      canvas.drawLine(
          Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(
          Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(
          covariant _CameraGridPainter oldDelegate) =>
      false;
}
