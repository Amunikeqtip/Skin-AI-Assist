import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../../core/providers/scan_providers.dart';
import '../../../core/services/image_quality_checker.dart';
import '../../../core/services/skin_classifier.dart';
import '../../../core/services/scan_store.dart';
import '../../../core/widgets/common.dart';

class ScanFlow extends ConsumerStatefulWidget {
  const ScanFlow({super.key});

  @override
  ConsumerState<ScanFlow> createState() => _ScanFlowState();
}

class _ScanFlowState extends ConsumerState<ScanFlow> {
  final _qualityChecker = const ImageQualityChecker();
  final _skinClassifier = const SkinClassifier();
  CameraController? _camera;
  XFile? image;
  ImageQualityReport? _qualityReport;
  String? area;
  String duration = 'Less than a week';
  bool itch = false;
  bool pain = false;
  bool swelling = false;
  bool changed = false;
  bool _cameraLoading = false;
  bool _isCapturing = false;
  bool _isCheckingQuality = false;
  bool _flashEnabled = false;
  bool _showGrid = true;
  bool _saving = false;
  bool _isAnalyzing = false;
  SkinPrediction? _prediction;
  String? _analysisError;
  String? _cameraError;
  Offset? _focusPoint;
  Timer? _focusTimer;
  final Set<String> _temporaryImagePaths = {};
  int step = 0;

  @override
  void dispose() {
    _focusTimer?.cancel();
    _camera?.dispose();
    unawaited(_cleanupTemporaryPhotos());
    super.dispose();
  }

  Future<void> _cleanupTemporaryPhotos() async {
    for (final path in _temporaryImagePaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Temporary cleanup is best-effort; no photo path is saved to Hive.
      }
    }
    _temporaryImagePaths.clear();
  }

  Future<void> _initializeCamera() async {
    if (_cameraLoading) return;
    setState(() {
      _cameraLoading = true;
      _cameraError = null;
    });

    CameraController? nextCamera;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
            'NoCamera', 'No camera is available.');
      }

      final description = cameras.firstWhere(
        (camera) =>
            camera.lensDirection ==
            CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      nextCamera = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await nextCamera.initialize();
      await nextCamera.setFocusMode(FocusMode.auto);
      await nextCamera.setFlashMode(FlashMode.off);

      if (!mounted) {
        await nextCamera.dispose();
        return;
      }

      _camera = nextCamera;
      setState(() {
        _cameraLoading = false;
        _flashEnabled = false;
      });
    } on CameraException catch (error) {
      await nextCamera?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = _cameraErrorMessage(error);
      });
    } catch (_) {
      await nextCamera?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError =
            'The camera could not be started. Check camera access and try again.';
      });
    }
  }

  String _cameraErrorMessage(CameraException error) {
    if (error.code.toLowerCase().contains('denied')) {
      return 'Camera access is turned off. Allow camera access in your device settings, then try again.';
    }
    return error.description ??
        'The camera could not be started. Please try again.';
  }

  Future<void> _releaseCamera() async {
    final currentCamera = _camera;
    _camera = null;
    _focusTimer?.cancel();
    if (currentCamera != null) {
      await currentCamera.dispose();
    }
  }

  Future<void> _capturePhoto() async {
    final currentCamera = _camera;
    if (currentCamera == null ||
        !currentCamera.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final captured = await currentCamera.takePicture();
      _temporaryImagePaths.add(captured.path);
      if (!mounted) {
        await _cleanupTemporaryPhotos();
        return;
      }
      setState(() {
        image = captured;
        _prediction = null;
        _analysisError = null;
        _qualityReport = null;
        _isCheckingQuality = true;
        _isCapturing = false;
      });

      final report = await _qualityChecker
          .inspect(File(captured.path));
      if (!mounted) return;
      setState(() {
        _qualityReport = report;
        _isCheckingQuality = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.description ??
                'Could not capture the photo.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _isCheckingQuality = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Could not check this photo. Please retake it.')),
      );
    }
  }

  Future<void> _cropPhoto() async {
    final currentImage = image;
    if (currentImage == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: currentImage.path,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(toolbarTitle: 'Crop photo'),
        IOSUiSettings(title: 'Crop photo'),
      ],
    );

    if (cropped == null) return;

    final croppedImage = XFile(cropped.path);
    _temporaryImagePaths.add(cropped.path);
    if (!mounted) {
      await _cleanupTemporaryPhotos();
      return;
    }
    setState(() {
      image = croppedImage;
      _prediction = null;
      _analysisError = null;
      _qualityReport = null;
      _isCheckingQuality = true;
    });

    try {
      final report =
          await _qualityChecker.inspect(File(cropped.path));
      if (!mounted) return;
      setState(() {
        _qualityReport = report;
        _isCheckingQuality = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingQuality = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Could not check the cropped photo.')),
      );
    }
  }

  Future<void> _toggleFlash() async {
    final currentCamera = _camera;
    if (currentCamera == null) return;

    final enabled = !_flashEnabled;
    try {
      await currentCamera.setFlashMode(
        enabled ? FlashMode.always : FlashMode.off,
      );
      if (mounted) setState(() => _flashEnabled = enabled);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Flash is not available on this camera.')),
      );
    }
  }

  Future<void> _focusCamera(Offset normalizedPoint) async {
    final currentCamera = _camera;
    if (currentCamera == null) return;

    _focusTimer?.cancel();
    setState(() => _focusPoint = normalizedPoint);
    try {
      await currentCamera.setFocusPoint(normalizedPoint);
      await currentCamera.setExposurePoint(normalizedPoint);
    } on CameraException {
      // The focus marker still shows where the user tapped if hardware
      // focus or exposure points are not supported by this camera.
    }
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  Future<void> _goBack() async {
    final previousStep = step - 1;
    if (step == 2) await _releaseCamera();
    if (!mounted) return;

    setState(() => step = previousStep);
    if (step == 2 && _camera == null) {
      await _initializeCamera();
    }
  }

  Future<void> _goNext() async {
    if (step == 0 && area == null) {
      _showMessage('Choose a body area to continue.');
      return;
    }
    if (step == 2 && image == null) {
      _showMessage('Capture a photo before continuing.');
      return;
    }
    if (step == 2 && _isCheckingQuality) {
      _showMessage(
          'Please wait while the photo quality is checked.');
      return;
    }

    if (step == 1) {
      setState(() => step++);
      await _initializeCamera();
      return;
    }
    if (step == 2) await _releaseCamera();
    if (!mounted) return;

    if (step == 3) {
      final selectedImage = image;
      setState(() => step++);
      if (selectedImage != null) {
        await _analyzePhoto(selectedImage);
      }
      return;
    }

    setState(() => step++);
  }

  Future<void> _analyzePhoto(XFile selectedImage) async {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
      _prediction = null;
    });

    try {
      final prediction = await _skinClassifier.classify(
        File(selectedImage.path),
      );
      if (!mounted) return;
      setState(() => _prediction = prediction);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _analysisError =
            'The model could not analyze this photo on this device. You can still save the visit without an AI result.',
      );
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveVisit() async {
    setState(() => _saving = true);

    try {
      await ref.read(scanHistoryProvider.notifier).save(
            ScanRecord(
              date: DateTime.now(),
              area: area ?? 'Not specified',
              symptoms: {
                'Itching': itch,
                'Pain': pain,
                'Swelling': swelling,
                'Recent change': changed,
              },
              duration: duration,
              prediction: _prediction?.topMatch.label,
              confidence: _prediction?.topMatch.score,
              risk: _prediction == null
                  ? null
                  : 'Not assessed',
            ),
          );

      await _releaseCamera();
      await _cleanupTemporaryPhotos();
      if (mounted) context.go('/history');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
          'Could not save this visit. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'About the area',
      'A few questions',
      'Take a photo',
      'Review photo',
      'AI result & save',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[step]),
        leading: step > 0
            ? IconButton(
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LinearProgressIndicator(
              value: (step + 1) / titles.length,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 22),
            const NoticeBanner(),
            const SizedBox(height: 18),
            if (step == 0) _buildAreaStep(context),
            if (step == 1) _buildQuestionStep(context),
            if (step == 2) _buildCaptureStep(context),
            if (step == 3) _buildReviewStep(context),
            if (step == 4) _buildSaveStep(context),
            if (step < 4) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _goNext,
                child:
                    Text(step == 3 ? 'Continue' : 'Next'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAreaStep(BuildContext context) {
    const areas = [
      'Face',
      'Neck',
      'Chest',
      'Back',
      'Arm',
      'Hand',
      'Leg',
      'Foot',
      'Other',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Where is the skin issue located?'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in areas)
              ChoiceChip(
                label: Text(item),
                selected: area == item,
                onSelected: (_) =>
                    setState(() => area = item),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuestionStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'What have you noticed?'),
        _check(
            'Does it itch?', itch, (value) => itch = value),
        _check(
            'Does it hurt?', pain, (value) => pain = value),
        _check('Is there swelling?', swelling,
            (value) => swelling = value),
        _check(
          'Has it changed recently?',
          changed,
          (value) => changed = value,
        ),
        const SizedBox(height: 10),
        const Text('How long has it been present?'),
        DropdownButtonFormField<String>(
          initialValue: duration,
          items: [
            'Less than a week',
            '1–4 weeks',
            '1–6 months',
            'More than 6 months',
            'Not sure',
          ]
              .map((item) => DropdownMenuItem(
                  value: item, child: Text(item)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => duration = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildCaptureStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Take a clear photo'),
        const Text(
          'Use bright, even lighting. Tap the affected area to focus, keep the camera steady, and include only the area you want to check.',
        ),
        const SizedBox(height: 18),
        _buildCameraPreview(context),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _flashEnabled
                  ? 'Turn flash off'
                  : 'Turn flash on',
              onPressed:
                  _camera == null ? null : _toggleFlash,
              icon: Icon(_flashEnabled
                  ? Icons.flash_on
                  : Icons.flash_off),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _showGrid = !_showGrid),
              icon: Icon(_showGrid
                  ? Icons.grid_on
                  : Icons.grid_off),
              label: Text(
                  _showGrid ? 'Hide grid' : 'Show grid'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _camera == null || _isCapturing
              ? null
              : _capturePhoto,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_isCapturing
              ? 'Capturing…'
              : 'Capture photo'),
        ),
        if (image != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isCapturing ? null : _capturePhoto,
            icon: const Icon(Icons.refresh),
            label: const Text('Retake photo'),
          ),
        ],
        if (_qualityReport != null) ...[
          const SizedBox(height: 10),
          _buildQualityMessage(),
        ],
        if (_isCheckingQuality)
          const LinearProgressIndicator(),
      ],
    );
  }

  Widget _buildCameraPreview(BuildContext context) {
    final camera = _camera;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.file(
          File(image!.path),
          height: 340,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      );
    }
    if (_cameraLoading) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_cameraError != null ||
        camera == null ||
        !camera.value.isInitialized) {
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
            Text(
              _cameraError ?? 'Camera is not ready.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _initializeCamera,
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
                _focusCamera(
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
                  CameraPreview(camera),
                  if (_showGrid)
                    const IgnorePointer(
                      child: CustomPaint(
                          painter: _CameraGridPainter()),
                    ),
                  if (_focusPoint case final point?)
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

  Widget _buildReviewStep(BuildContext context) {
    final selectedImage = image;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Review your photo'),
        if (selectedImage != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.file(
              File(selectedImage.path),
              height: 320,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Check that the image is sharp, well lit, and shows the area clearly. Basic checks cannot confirm that a photo is suitable for medical assessment.',
        ),
        if (_isCheckingQuality) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else if (_qualityReport != null) ...[
          const SizedBox(height: 12),
          _buildQualityMessage(),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isCheckingQuality ? null : _cropPhoto,
          icon: const Icon(Icons.crop),
          label: const Text('Crop photo'),
        ),
        TextButton.icon(
          onPressed: _isCheckingQuality
              ? null
              : () async {
                  setState(() {
                    image = null;
                    _prediction = null;
                    _analysisError = null;
                    _qualityReport = null;
                    step = 2;
                  });
                  await _initializeCamera();
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Retake photo'),
        ),
      ],
    );
  }

  Widget _buildQualityMessage() {
    final report = _qualityReport!;
    final color = report.isAcceptable
        ? Colors.green
        : Colors.deepOrange;
    return Card(
      color: color.withValues(alpha: .1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              report.isAcceptable
                  ? Icons.check_circle_outline
                  : Icons.warning_amber,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(report.message)),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 52,
              color: Colors.teal,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _title(context, 'Experimental AI output'),
        const Text(
          'MobileNetV3-Large was trained on PAD-UFES-20 smartphone images. It is running locally for an educational prototype. Model scores are not medical probabilities or a diagnosis.',
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Research prototype only'),
            subtitle: const Text(
              'This model correctly identified 4 of 9 melanoma and 5 of 32 squamous cell carcinoma images in its patient-held-out evaluation. A low score or a benign-looking result does not rule out cancer. Consult a healthcare professional about concerning changes.',
            ),
          ),
        ),
        if (_isAnalyzing) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                      child:
                          Text('Running on-device model…')),
                ],
              ),
            ),
          ),
        ] else if (_prediction case final prediction?) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top model match: ${prediction.topMatch.label}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Uncalibrated model scores'),
                  const SizedBox(height: 12),
                  for (final item
                      in prediction.scores.take(3)) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 132,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: item.score
                                .clamp(0.0, 1.0)
                                .toDouble(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                            '${(item.score * 100).round()}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          const Text(
            'The photo is analyzed on this device and is not saved to visit history. It is not sent to a server.',
          ),
        ] else if (_analysisError case final error?) ...[
          Card(
            color: Theme.of(context)
                .colorScheme
                .errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              _saving || _isAnalyzing ? null : _saveVisit,
          child: Text(_saving
              ? 'Saving…'
              : 'Save visit to history'),
        ),
      ],
    );
  }

  Widget _title(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .headlineSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _check(String title, bool value,
      ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: (newValue) =>
          setState(() => onChanged(newValue ?? false)),
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
