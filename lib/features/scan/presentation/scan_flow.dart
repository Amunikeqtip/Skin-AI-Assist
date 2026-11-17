import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/scan_providers.dart';
import '../../../core/services/image_quality_checker.dart';
import '../../../core/services/pad_analysis_service.dart';
import '../../../core/services/skin_pixel_gate.dart';
import '../../../core/services/skin_classifier.dart';
import '../../../core/services/scan_store.dart';
import '../../../core/widgets/common.dart';
import 'widgets/pad_analysis_result_panel.dart';
import 'widgets/scan_camera_preview.dart';

class ScanFlow extends ConsumerStatefulWidget {
  const ScanFlow({super.key});

  @override
  ConsumerState<ScanFlow> createState() => _ScanFlowState();
}

class _ScanFlowState extends ConsumerState<ScanFlow> {
  final _qualityChecker = const ImageQualityChecker();
  final _analysisService = const PadAnalysisService();
  final _imagePicker = ImagePicker();
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
  String? _analysisStage;
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

  Future<void> _pickFromGallery() async {
    if (_isAnalyzing ||
        _isCapturing ||
        _isCheckingQuality) {
      return;
    }

    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (selected == null) return;
      _temporaryImagePaths.add(selected.path);

      if (!mounted) {
        await _cleanupTemporaryPhotos();
        return;
      }
      setState(() {
        image = selected;
        _prediction = null;
        _analysisError = null;
        _analysisStage = null;
        _qualityReport = null;
        _isCheckingQuality = true;
      });

      final report = await _qualityChecker
          .inspect(File(selected.path));
      if (!mounted) return;
      setState(() {
        _qualityReport = report;
        _isCheckingQuality = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingQuality = false);
      _showMessage(
          'Could not open or check that gallery photo. Please try another image.');
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
    if (step == 2 &&
        _qualityReport?.isAcceptable == false) {
      _showMessage(
        'Retake the photo so it passes the basic quality checks before analysis.',
      );
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
      _analysisStage = 'quality';
    });

    try {
      final prediction = await _analysisService.analyze(
        File(selectedImage.path),
        onStage: (stage) {
          if (mounted) {
            setState(() => _analysisStage = stage);
          }
        },
      );
      if (!mounted) return;
      setState(() => _prediction = prediction);
    } on NoSkinDetectedException {
      if (!mounted) return;
      setState(() {
        _analysisStage = 'failed';
        _analysisError =
            'The experimental skin gate did not find enough skin-coloured pixels. Use a closer photo of the selected area, or retake it in even lighting.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analysisStage = 'failed';
        _analysisError =
            'The skin check or PAD model could not analyze this photo on this device. You can still save the visit without an AI result.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          if (_prediction != null) {
            _analysisStage = 'complete';
          }
        });
      }
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              _isCheckingQuality ? null : _pickFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Upload from gallery'),
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
    return ScanCameraPreview(
      camera: _camera,
      imagePath: image?.path,
      isLoading: _cameraLoading,
      error: _cameraError,
      showGrid: _showGrid,
      focusPoint: _focusPoint,
      onRetry: _initializeCamera,
      onFocus: _focusCamera,
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
        OutlinedButton.icon(
          onPressed:
              _isCheckingQuality ? null : _pickFromGallery,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text(
              'Choose a different gallery photo'),
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
    return PadAnalysisResultPanel(
      prediction: _prediction,
      isAnalyzing: _isAnalyzing,
      analysisError: _analysisError,
      analysisStage: _analysisStage,
      imagePath: image?.path,
      isSaving: _saving,
      onSave: _saveVisit,
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
