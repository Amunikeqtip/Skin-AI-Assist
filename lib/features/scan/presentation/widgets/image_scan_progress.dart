import 'dart:io';

import 'package:flutter/material.dart';

/// Displays the selected photo with an animated scan line while local
/// image checks and the experimental classifier are running.
class ImageScanProgress extends StatefulWidget {
  const ImageScanProgress({
    required this.imagePath,
    super.key,
  });

  final String? imagePath;

  @override
  State<ImageScanProgress> createState() =>
      _ImageScanProgressState();
}

class _ImageScanProgressState
    extends State<ImageScanProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.imagePath;
    if (imagePath == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(imagePath),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(
                color: colors.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 44),
                ),
              ),
            ),
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Align(
                  alignment: Alignment(
                      0, (_controller.value * 1.8) - 0.9),
                  child: child,
                ),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary
                            .withValues(alpha: .7),
                        blurRadius: 14,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Align(
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 9),
                        Text(
                          'Scanning image…',
                          style: TextStyle(
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
