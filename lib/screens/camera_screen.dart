import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/timer_selector.dart';
import '../widgets/quality_selector.dart';
import '../widgets/storage_selector.dart';
import '../widgets/timestamp_selector.dart';
import '../widgets/hdr_selector.dart';
import '../widgets/filter_selector.dart';
import '../widgets/stabilization_selector.dart';
import '../widgets/zoom_selector.dart';
import 'preview_screen.dart';

enum CameraMode { photo, video }

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Controller ──────────────────────────────────────────────────────────────
  CameraController? _controller;
  int _cameraIndex = 0;
  ResolutionPreset _resolution = ResolutionPreset.veryHigh;

  // ── Mode ────────────────────────────────────────────────────────────────────
  CameraMode _mode = CameraMode.photo;

  // ── Zoom (0.5x, 1x, 2x, 4x, 10x - Default 1x) ──────────────────────────────
  double _currentZoom = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 10.0;
  double _baseScale = 1.0;

  // ── Photo timer ─────────────────────────────────────────────────────────────
  final List<String> _photoTimerOptions = ['Tắt', '3s', '5s', '10s', '15s'];
  String _selectedPhotoTimer = 'Tắt';
  Timer? _photoCountdownTimer;
  int _photoCountdown = 0;
  bool _isPhotoCountingDown = false;

  // ── Burst / continuous shooting ──────────────────────────────────────────────
  final List<int> _burstOptions = [0, 3, 5, 7, 9, 15]; // 0 = off
  int _burstCount = 0; // number of frames; 0 means disabled
  bool _isBursting = false;
  int _burstProgress = 0; // frames captured so far
  int _burstTotal = 0;    // frames requested for current burst

  // ── Video duration ───────────────────────────────────────────────────────────
  final List<String> _videoDurationOptions = [
    'Tắt', '15s', '30s', '1 phút', '3 phút', '5 phút', '10 phút',
  ];
  String _selectedVideoDuration = 'Tắt';

  // ── Recording state ──────────────────────────────────────────────────────────
  bool _isRecording = false;
  int _recordingElapsed = 0;
  Timer? _recordingTimer;
  Timer? _autoStopTimer;

  // ── UI state ─────────────────────────────────────────────────────────────────
  bool _isInitializing = true;
  bool _showSettings = false;
  bool _showGrid = false;
  bool _showFilterBar = false;
  bool _isTakingPhoto = false;
  String? _lastSavedPath;
  bool _lastSavedIsVideo = false;

  // ── Beauty & Color Filters ───────────────────────────────────────────────────
  CameraFilter _selectedFilter = CameraFilter.none;

  // ── Image Stabilization (OIS / EIS / Super Steady) ───────────────────────────
  StabilizationMode _stabilizationMode = StabilizationMode.standard;

  // ── Storage location ──────────────────────────────────────────────────────────
  StorageLocation _storageLocation = StorageLocation.phone;
  bool _sdcardAvailable = false;
  String? _sdcardAppPath;
  String? _sdcardRootPath;

  // ── Timestamp watermark ───────────────────────────────────────────────────────
  bool _showTimestamp = true;

  // ── HDR Mode ─────────────────────────────────────────────────────────────────
  HdrMode _hdrMode = HdrMode.auto;

  // ── Mirror / Selfie Flip (front camera) ─────────────────────────────────────
  /// Lật ảnh ngang khi dùng camera trước. Mặc định bật khi chụp bằng camera trước.
  bool _mirrorFrontCamera = true;

  // Helper: is current camera the front (selfie) camera?
  bool get _isFrontCamera =>
      widget.cameras.isNotEmpty &&
      _cameraIndex < widget.cameras.length &&
      widget.cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  // ── Flash ────────────────────────────────────────────────────────────────────
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _detectSdCard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _photoCountdownTimer?.cancel();
    _recordingTimer?.cancel();
    _autoStopTimer?.cancel();
    _controller?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── SD Card detection ────────────────────────────────────────────────────────
  Future<void> _detectSdCard() async {
    if (!Platform.isAndroid) return;
    try {
      final sdRoots = <String>{};

      // 1. Direct /storage mount points scan (finds real physical SD cards)
      try {
        final storageDir = Directory('/storage');
        if (storageDir.existsSync()) {
          for (final entity in storageDir.listSync()) {
            if (entity is Directory) {
              final name = path.basename(entity.path);
              if (name != 'emulated' &&
                  name != 'self' &&
                  name != 'knox' &&
                  name != 'container' &&
                  !name.startsWith('.')) {
                sdRoots.add(entity.path);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('/storage mount scan: $e');
      }

      // 2. Query path_provider external storage directories
      try {
        final picDirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
        if (picDirs != null) {
          for (final dir in picDirs) {
            if (!dir.path.contains('/emulated/0')) {
              _sdcardAppPath = dir.path;
              final root = dir.path.split('Android').first;
              if (root.isNotEmpty) {
                sdRoots.add(root.endsWith('/') ? root.substring(0, root.length - 1) : root);
              }
            }
          }
        }
      } catch (_) {}

      try {
        final rawDirs = await getExternalStorageDirectories();
        if (rawDirs != null && rawDirs.length > 1) {
          final sdDir = rawDirs[1];
          _sdcardAppPath ??= sdDir.path;
          final root = sdDir.path.split('Android').first;
          if (root.isNotEmpty) {
            sdRoots.add(root.endsWith('/') ? root.substring(0, root.length - 1) : root);
          }
        }
      } catch (_) {}

      if (sdRoots.isNotEmpty) {
        _sdcardRootPath = sdRoots.first;
        setState(() {
          _sdcardAvailable = true;
        });
        debugPrint('SD Card detected: root=$_sdcardRootPath, appPath=$_sdcardAppPath');
        return;
      }
    } catch (e) {
      debugPrint('SD Card detection error: $e');
    }

    setState(() {
      _sdcardAvailable = false;
      _sdcardAppPath = null;
      _sdcardRootPath = null;
      // Fall back to phone if SD was previously selected
      if (_storageLocation == StorageLocation.sdcard) {
        _storageLocation = StorageLocation.phone;
      }
    });
  }

  // ── Permissions ──────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.manageExternalStorage,
    ].request();

    final camOk = await Permission.camera.isGranted;
    final micOk = await Permission.microphone.isGranted;

    if (camOk && micOk) {
      _initCamera();
      _detectSdCard();
    } else {
      setState(() => _isInitializing = false);
      if (mounted) {
        _showSnackbar('Cần cấp quyền Camera và Microphone', Colors.red);
      }
    }
  }

  // ── Init camera ───────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _isInitializing = false);
      return;
    }
    await _controller?.dispose();

    final controller = CameraController(
      widget.cameras[_cameraIndex],
      _resolution,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      // Query hardware zoom capabilities (Default 1x)
      try {
        final minZ = await controller.getMinZoomLevel();
        final maxZ = await controller.getMaxZoomLevel();
        _minAvailableZoom = minZ;
        _maxAvailableZoom = maxZ.clamp(1.0, 10.0);
        _currentZoom = 1.0.clamp(minZ, _maxAvailableZoom);
        await controller.setZoomLevel(_currentZoom);
      } catch (e) {
        debugPrint('Zoom level query error: $e');
      }

      if (mounted) setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  // ── Set Zoom Level (0.5x, 1x, 2x, 4x, 10x) ──────────────────────────────────
  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final targetZoom = zoom.clamp(_minAvailableZoom, _maxAvailableZoom);
    setState(() => _currentZoom = zoom);
    try {
      await _controller!.setZoomLevel(targetZoom);
    } catch (e) {
      debugPrint('Set zoom error: $e');
    }
  }

  // ── Switch camera ─────────────────────────────────────────────────────────────
  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final nextIndex = _cameraIndex == 0 ? 1 : 0;
    final nextIsFront = nextIndex < widget.cameras.length &&
        widget.cameras[nextIndex].lensDirection == CameraLensDirection.front;
    setState(() {
      _cameraIndex = nextIndex;
      _isInitializing = true;
      // Auto-enable mirror when switching to front camera
      if (nextIsFront) _mirrorFrontCamera = true;
    });
    await _initCamera();
  }

  // ── HDR toggle helper ────────────────────────────────────────────────────────
  void _cycleHdrMode() {
    setState(() {
      switch (_hdrMode) {
        case HdrMode.auto:
          _hdrMode = HdrMode.on;
          break;
        case HdrMode.on:
          _hdrMode = HdrMode.off;
          break;
        case HdrMode.off:
          _hdrMode = HdrMode.auto;
          break;
      }
    });
  }

  // ── Stabilization Mode (OIS / EIS / Super Steady) ─────────────────────────
  void _cycleStabilizationMode() {
    setState(() {
      switch (_stabilizationMode) {
        case StabilizationMode.off:
          _stabilizationMode = StabilizationMode.standard;
          break;
        case StabilizationMode.standard:
          _stabilizationMode = StabilizationMode.superSteady;
          break;
        case StabilizationMode.superSteady:
          _stabilizationMode = StabilizationMode.off;
          break;
      }
    });
    _applyStabilization();
  }

  Future<void> _applyStabilization() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_stabilizationMode != StabilizationMode.off) {
        await _controller!.setFocusMode(FocusMode.auto);
        await _controller!.setExposureMode(ExposureMode.auto);
      }
    } catch (e) {
      debugPrint('Stabilization apply error: $e');
    }
  }

  // ── Flash ─────────────────────────────────────────────────────────────────────
  void _toggleFlash() {
    if (_mode == CameraMode.photo) {
      final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
      final next = modes[(modes.indexOf(_flashMode) + 1) % modes.length];
      setState(() => _flashMode = next);
      _controller?.setFlashMode(next);
    } else {
      final next = _flashMode == FlashMode.torch || _flashMode == FlashMode.always
          ? FlashMode.off
          : FlashMode.torch;
      setState(() => _flashMode = next);
      _controller?.setFlashMode(next);
    }
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  // ── Duration helpers ──────────────────────────────────────────────────────────
  int _photoTimerSeconds(String s) =>
      {'3s': 3, '5s': 5, '10s': 10, '15s': 15}[s] ?? 0;

  int _videoDurationSeconds(String s) =>
      {'15s': 15, '30s': 30, '1 phút': 60, '3 phút': 180, '5 phút': 300, '10 phút': 600}[s] ?? 0;

  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ── Save directory ────────────────────────────────────────────────────────────
  Future<String> _getSaveDir(bool isVideo) async {
    const appFolder = 'CameraApp2026';
    final mediaTypeFolder = isVideo ? 'Movies' : 'Pictures';

    if (Platform.isAndroid) {
      // ── 1. If MicroSD Card is selected ──
      if (_storageLocation == StorageLocation.sdcard) {
        final sdCandidates = <String>[];

        // Public folders on SD Card (DCIM / Pictures / Movies / CameraApp2026)
        if (_sdcardRootPath != null) {
          sdCandidates.add(path.join(_sdcardRootPath!, 'DCIM', appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, mediaTypeFolder, appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, appFolder));
        }

        // App-specific folder on SD Card (guaranteed write access on Android 10+)
        if (_sdcardAppPath != null) {
          sdCandidates.add(path.join(_sdcardAppPath!, appFolder));
          sdCandidates.add(path.join(_sdcardAppPath!, mediaTypeFolder, appFolder));
          sdCandidates.add(_sdcardAppPath!);
        }

        // Package specific paths on SD
        if (_sdcardRootPath != null) {
          sdCandidates.add(path.join(_sdcardRootPath!, 'Android', 'data', 'com.example.camera_app', 'files', appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, 'Android', 'media', 'com.example.camera_app', appFolder));
        }

        for (final candidate in sdCandidates) {
          try {
            final dir = Directory(candidate);
            if (!dir.existsSync()) {
              dir.createSync(recursive: true);
            }
            final testFile = File(path.join(dir.path, '.test_${DateTime.now().millisecondsSinceEpoch}'));
            testFile.writeAsStringSync('ok');
            if (testFile.existsSync()) {
              testFile.deleteSync();
            }
            debugPrint('Valid writable SD card directory: ${dir.path}');
            return dir.path;
          } catch (e) {
            debugPrint('SD write candidate $candidate rejected: $e');
          }
        }
        debugPrint('SD card write candidates rejected, falling back to phone storage');
      }

      // ── 2. Internal Phone Storage ──
      final phoneCandidates = <String>[
        '/storage/emulated/0/DCIM/$appFolder',
        '/storage/emulated/0/$mediaTypeFolder/$appFolder',
        '/storage/emulated/0/$appFolder',
      ];

      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final root = ext.path.split('Android').first;
          phoneCandidates.insert(0, path.join(root, 'DCIM', appFolder));
          phoneCandidates.insert(1, path.join(root, mediaTypeFolder, appFolder));
          phoneCandidates.add(path.join(ext.path, appFolder));
        }
      } catch (_) {}

      for (final candidate in phoneCandidates) {
        try {
          final dir = Directory(candidate);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          final testFile = File(path.join(dir.path, '.test_${DateTime.now().millisecondsSinceEpoch}'));
          testFile.writeAsStringSync('ok');
          if (testFile.existsSync()) {
            testFile.deleteSync();
          }
          debugPrint('Valid writable phone directory: ${dir.path}');
          return dir.path;
        } catch (e) {
          debugPrint('Phone write candidate $candidate rejected: $e');
        }
      }
    }

    // ── 3. Fallback: Application Documents Directory ──
    final appDocDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(path.join(appDocDir.path, appFolder));
    if (!fallbackDir.existsSync()) {
      fallbackDir.createSync(recursive: true);
    }
    return fallbackDir.path;
  }

  // ── Photo capture ─────────────────────────────────────────────────────────────
  Future<void> _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isBursting) return; // ignore taps during burst
    if (_isPhotoCountingDown) {
      _cancelPhotoCountdown();
      return;
    }
    final delay = _photoTimerSeconds(_selectedPhotoTimer);
    if (delay == 0) {
      if (_burstCount > 0) {
        await _takeBurstPhotos(_burstCount);
      } else {
        await _takePhoto();
      }
    } else {
      _startPhotoCountdown(delay);
    }
  }

  void _startPhotoCountdown(int seconds) {
    setState(() {
      _photoCountdown = seconds;
      _isPhotoCountingDown = true;
    });
    _photoCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_photoCountdown <= 1) {
        t.cancel();
        setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
        if (_burstCount > 0) {
          _takeBurstPhotos(_burstCount);
        } else {
          _takePhoto();
        }
      } else {
        setState(() => _photoCountdown--);
      }
    });
  }

  void _cancelPhotoCountdown() {
    _photoCountdownTimer?.cancel();
    setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
  }

  // ── Photo Post-Processing: Beauty Filter, HDR Low-Light, Timestamp & Mirror ─
  Future<void> _processCapturedPhoto(String sourcePath, String destPath) async {
    final applyHdr = _hdrMode == HdrMode.on || _hdrMode == HdrMode.auto;
    final applyTimestamp = _showTimestamp;
    final filterMatrix = FilterHelper.getMatrix(_selectedFilter);
    final applyFilter = filterMatrix != null;
    // Mirror flip: apply when front camera AND mirror setting is enabled
    final applyMirror = _isFrontCamera && _mirrorFrontCamera;

    if (!applyHdr && !applyTimestamp && !applyFilter && !applyMirror) {
      await File(sourcePath).copy(destPath);
      return;
    }

    try {
      final bytes = await File(sourcePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Apply horizontal mirror flip for front camera selfie
      if (applyMirror) {
        canvas.save();
        canvas.translate(image.width.toDouble(), 0);
        canvas.scale(-1.0, 1.0);
      }

      // 1. Base image layer (with color/beauty filter if selected)
      final basePaint = Paint();
      if (applyFilter) {
        basePaint.colorFilter = ColorFilter.matrix(filterMatrix);
      }
      canvas.drawImage(image, Offset.zero, basePaint);

      if (applyHdr) {
        // 2. HDR Shadow Recovery layer (Screen blend + brightness offset in dark regions)
        final hdrShadowPaint = Paint()
          ..blendMode = BlendMode.screen
          ..colorFilter = const ColorFilter.matrix(<double>[
            0.30, 0.0, 0.0, 0.0, 18,
            0.0, 0.30, 0.0, 0.0, 18,
            0.0, 0.0, 0.30, 0.0, 18,
            0.0, 0.0, 0.0, 1.0, 0,
          ]);
        canvas.drawImage(image, Offset.zero, hdrShadowPaint);

        // 3. Dynamic contrast & color vibrancy enhancement (SoftLight blend)
        final hdrVibrancePaint = Paint()
          ..blendMode = BlendMode.softLight
          ..colorFilter = const ColorFilter.matrix(<double>[
            1.10, 0.0, 0.0, 0.0, 0,
            0.0, 1.10, 0.0, 0.0, 0,
            0.0, 0.0, 1.10, 0.0, 0,
            0.0, 0.0, 0.0, 1.0, 0,
          ]);
        canvas.drawImage(image, Offset.zero, hdrVibrancePaint);
      }

      // Restore canvas transform after mirror
      if (applyMirror) {
        canvas.restore();
      }

      // 4. Timestamp Watermark (if enabled)
      if (applyTimestamp) {
        final now = DateTime.now();
        final dateStr =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final fontSize = (image.width * 0.026).clamp(24.0, 72.0);
        final padding = fontSize * 0.8;

        final textSpan = TextSpan(
          text: dateStr,
          style: TextStyle(
            color: const Color(0xFFFFD700),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            shadows: const [
              Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 4),
              Shadow(color: Colors.black87, offset: Offset(-1, -1), blurRadius: 3),
            ],
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final x = image.width - textPainter.width - padding;
        final y = image.height - textPainter.height - padding;

        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - padding * 0.4,
            y - padding * 0.25,
            textPainter.width + padding * 0.8,
            textPainter.height + padding * 0.5,
          ),
          Radius.circular(padding * 0.35),
        );
        canvas.drawRRect(
          bgRect,
          Paint()..color = Colors.black.withAlpha(120),
        );

        textPainter.paint(canvas, Offset(x, y));
      }

      final picture = recorder.endRecording();
      final outputImage = await picture.toImage(image.width, image.height);
      final byteData = await outputImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        await File(destPath).writeAsBytes(byteData.buffer.asUint8List());
      } else {
        await File(sourcePath).copy(destPath);
      }
    } catch (e) {
      debugPrint('Photo processing error: $e, fallback to copy');
      await File(sourcePath).copy(destPath);
    }
  }

  // ── Single photo ──────────────────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTakingPhoto = true);
    try {
      final xFile = await _controller!.takePicture();
      final dir = await _getSaveDir(false);
      final filePath = path.join(dir, 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      await _processCapturedPhoto(xFile.path, filePath);

      setState(() { _isTakingPhoto = false; _lastSavedPath = filePath; _lastSavedIsVideo = false; });
      if (mounted) {
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        final hdrText = _hdrMode != HdrMode.off ? ' (HDR)' : '';
        _showSnackbar('✅ Đã lưu ảnh$hdrText vào $locText', Colors.green);
        _openPreview(filePath, false);
      }
    } catch (e) {
      setState(() => _isTakingPhoto = false);
      debugPrint('Take photo error: $e');
      if (mounted) {
        _showSnackbar('❌ Lỗi khi lưu ảnh: $e', Colors.red);
      }
    }
  }

  // ── Burst shooting ────────────────────────────────────────────────────────────
  Future<void> _takeBurstPhotos(int count) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isBursting = true;
      _burstProgress = 0;
      _burstTotal = count;
    });
    final dir = await _getSaveDir(false);
    String? lastPath;
    int saved = 0;
    for (int i = 0; i < count; i++) {
      if (!mounted || _controller == null) break;
      try {
        setState(() { _isTakingPhoto = true; _burstProgress = i + 1; });
        final xFile = await _controller!.takePicture();
        final filePath = path.join(dir, 'BURST_${DateTime.now().millisecondsSinceEpoch}_${i + 1}.jpg');
        
        await _processCapturedPhoto(xFile.path, filePath);

        lastPath = filePath;
        saved++;
        setState(() => _isTakingPhoto = false);
        // short gap between frames (~300 ms)
        if (i < count - 1) await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        setState(() => _isTakingPhoto = false);
        debugPrint('Burst frame ${i + 1} error: $e');
      }
    }
    setState(() {
      _isBursting = false;
      _burstProgress = 0;
      _burstTotal = 0;
      if (lastPath != null) {
        _lastSavedPath = lastPath;
        _lastSavedIsVideo = false;
      }
    });
    if (mounted) {
      if (saved > 0) {
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        final hdrText = _hdrMode != HdrMode.off ? ' (HDR)' : '';
        _showSnackbar('✅ Đã lưu $saved/$count ảnh$hdrText vào $locText', Colors.green);
      } else {
        _showSnackbar('❌ Không thể lưu ảnh chụp liên tiếp', Colors.red);
      }
    }
  }

  // ── Video recording ───────────────────────────────────────────────────────────
  Future<void> _handleVideoButton() async {
    _isRecording ? await _stopRecording() : await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.startVideoRecording();
      WakelockPlus.enable();
      setState(() { _isRecording = true; _recordingElapsed = 0; });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingElapsed++);
      });
      final limit = _videoDurationSeconds(_selectedVideoDuration);
      if (limit > 0) {
        _autoStopTimer = Timer(Duration(seconds: limit), () {
          if (_isRecording) _stopRecording();
        });
      }
    } on CameraException catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_isRecording) return;
    _recordingTimer?.cancel();
    _autoStopTimer?.cancel();

    // Mark not recording immediately so UI updates and double-stop is prevented
    setState(() { _isRecording = false; _recordingElapsed = 0; });

    XFile? xFile;
    try {
      xFile = await _controller!.stopVideoRecording();
    } catch (e) {
      WakelockPlus.disable();
      debugPrint('stopVideoRecording error: $e');
      if (mounted) _showSnackbar('❌ Lỗi dừng ghi video: $e', Colors.red);
      return;
    }

    WakelockPlus.disable();

    // Show saving progress (especially important for large SD card writes)
    if (mounted) {
      _showSnackbar('💾 Đang lưu video, vui lòng chờ...', Colors.blueGrey);
    }

    try {
      final srcPath = xFile.path;
      final srcFile = File(srcPath);

      // Validate source file exists and has content
      if (!srcFile.existsSync() || srcFile.lengthSync() == 0) {
        throw Exception('File video tạm rỗng hoặc không tồn tại: $srcPath');
      }

      final srcSize = srcFile.lengthSync();
      debugPrint('Video source: $srcPath (${(srcSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Resolve destination directory
      final dir = await _getSaveDir(true);
      final fileName = 'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final destPath = path.join(dir, fileName);

      // ── Streaming copy: chunk-by-chunk to avoid OOM on large files ──
      // This is critical for SD card: File.copy() can crash with > 100 MB files
      // because Android imposes cross-filesystem copy size limits.
      await _streamCopyFile(srcPath, destPath);

      // Validate destination was written correctly (at least 95% of source size)
      final destFile = File(destPath);
      final destSize = destFile.existsSync() ? destFile.lengthSync() : 0;
      if (destSize < (srcSize * 0.95).toInt()) {
        throw Exception(
          'File đích không đủ dung lượng: ${(destSize / 1024 / 1024).toStringAsFixed(1)} MB '
          '/ ${(srcSize / 1024 / 1024).toStringAsFixed(1)} MB',
        );
      }

      debugPrint('Video saved: $destPath (${(destSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Clean up source temp file to free camera temp storage
      try { srcFile.deleteSync(); } catch (_) {}

      if (mounted) {
        setState(() { _lastSavedPath = destPath; _lastSavedIsVideo = true; });
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        _showSnackbar('✅ Đã lưu video vào $locText', Colors.green);
        _openPreview(destPath, true);
      }
    } catch (e) {
      debugPrint('Save video error: $e');
      if (mounted) {
        // Try fallback: save to phone internal storage instead
        await _saveVideoFallbackToPhone(xFile.path, e.toString());
      }
    }
  }

  /// Streams a file copy chunk-by-chunk so large video files (hundreds of MB)
  /// are transferred without loading everything into RAM or blocking the main thread.
  Future<void> _streamCopyFile(String srcPath, String destPath) async {
    final src = File(srcPath);
    final dest = File(destPath);

    // Ensure parent directory exists
    final parent = dest.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final input = src.openRead();
    final output = dest.openWrite();
    try {
      // pipe() streams chunk-by-chunk and automatically calls close() on the sink
      // when done, ensuring all data is flushed and committed — do NOT call
      // flush() or close() again after pipe() or it will throw StateError.
      await input.pipe(output);
    } catch (e) {
      // Clean up partial destination file on error
      try {
        // output may or may not be closed depending on where the error occurred
        if (dest.existsSync()) dest.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Fallback: if SD card save fails, attempt to save to phone internal storage.
  Future<void> _saveVideoFallbackToPhone(String srcPath, String originalError) async {
    debugPrint('Attempting phone storage fallback after: $originalError');
    try {
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) {
        _showSnackbar('❌ Lỗi lưu video: file tạm không còn tồn tại', Colors.red);
        return;
      }

      // Temporarily force phone storage for this save
      final prevStorage = _storageLocation;
      _storageLocation = StorageLocation.phone;
      final dir = await _getSaveDir(true);
      _storageLocation = prevStorage;

      final fileName = 'VID_RECOVERY_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final destPath = path.join(dir, fileName);

      await _streamCopyFile(srcPath, destPath);
      try { srcFile.deleteSync(); } catch (_) {}

      if (mounted) {
        setState(() { _lastSavedPath = destPath; _lastSavedIsVideo = true; });
        _showSnackbar(
          '⚠️ SD card lỗi — Đã tự động lưu vào điện thoại thay thế',
          Colors.orange,
        );
        _openPreview(destPath, true);
      }
    } catch (fallbackError) {
      debugPrint('Fallback also failed: $fallbackError');
      if (mounted) {
        _showSnackbar(
          '❌ Không thể lưu video: SD card lỗi & điện thoại cũng thất bại.\n$originalError',
          Colors.red,
        );
      }
    }
  }

  void _openPreview(String filePath, bool isVideo) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PreviewScreen(filePath: filePath, isVideo: isVideo),
    ));
  }

  void _showSnackbar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Change quality ─────────────────────────────────────────────────────────────
  Future<void> _changeQuality(ResolutionPreset preset) async {
    if (_isRecording) return;
    setState(() { _resolution = preset; _isInitializing = true; });
    await _initCamera();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(),
          Expanded(child: _buildPreviewArea()),
          _buildBottomControls(),
        ]),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Left: Flash, HDR, Filter, Stabilization, and Title (Scrollable) ──
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _flashIcon,
                      color: _flashMode != FlashMode.off ? const Color(0xFFFFD700) : Colors.white,
                    ),
                    onPressed: _toggleFlash,
                    tooltip: _mode == CameraMode.photo ? 'Đèn Flash' : 'Đèn chiếu sáng (Torch)',
                  ),
                  if (_mode == CameraMode.photo) ...[
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: _cycleHdrMode,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: _hdrMode != HdrMode.off
                              ? const Color(0xFFFFD700).withAlpha(35)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _hdrMode != HdrMode.off
                                ? const Color(0xFFFFD700)
                                : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _hdrMode == HdrMode.on
                                  ? Icons.hdr_on
                                  : _hdrMode == HdrMode.auto
                                      ? Icons.hdr_auto
                                      : Icons.hdr_off,
                              size: 14,
                              color: _hdrMode != HdrMode.off
                                  ? const Color(0xFFFFD700)
                                  : Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _hdrMode == HdrMode.on
                                  ? 'HDR'
                                  : _hdrMode == HdrMode.auto
                                      ? 'HDR A'
                                      : 'HDR TẮT',
                              style: TextStyle(
                                color: _hdrMode != HdrMode.off
                                    ? const Color(0xFFFFD700)
                                    : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  // Nút bật/tắt thanh chọn Filter & Làm đẹp
                  GestureDetector(
                    onTap: () => setState(() => _showFilterBar = !_showFilterBar),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: _selectedFilter != CameraFilter.none || _showFilterBar
                            ? const Color(0xFFFFD700).withAlpha(35)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedFilter != CameraFilter.none || _showFilterBar
                              ? const Color(0xFFFFD700)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: _selectedFilter != CameraFilter.none || _showFilterBar
                                ? const Color(0xFFFFD700)
                                : Colors.white70,
                          ),
                          if (_selectedFilter != CameraFilter.none) ...[
                            const SizedBox(width: 3),
                            Text(
                              FilterHelper.getLabel(_selectedFilter),
                              style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Nút chuyển nhanh Chống Rung OIS / Super Steady
                  GestureDetector(
                    onTap: _cycleStabilizationMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: _stabilizationMode != StabilizationMode.off
                            ? const Color(0xFFFFD700).withAlpha(35)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _stabilizationMode != StabilizationMode.off
                              ? const Color(0xFFFFD700)
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _stabilizationMode == StabilizationMode.superSteady
                                ? Icons.motion_photos_auto
                                : _stabilizationMode == StabilizationMode.standard
                                    ? Icons.motion_photos_on
                                    : Icons.motion_photos_off,
                            size: 14,
                            color: _stabilizationMode != StabilizationMode.off
                                ? const Color(0xFFFFD700)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _stabilizationMode == StabilizationMode.superSteady
                                ? 'STEADY'
                                : _stabilizationMode == StabilizationMode.standard
                                    ? 'OIS'
                                    : 'OIS TẮT',
                            style: TextStyle(
                              color: _stabilizationMode != StabilizationMode.off
                                  ? const Color(0xFFFFD700)
                                  : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Recording Timer or Mode Title
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(_recordingElapsed),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (_selectedVideoDuration != 'Tắt')
                            Text(
                              ' / $_selectedVideoDuration',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        _mode == CameraMode.photo ? 'CHỤP ẢNH' : 'QUAY VIDEO',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 6),

          // ── Right: Grid & Settings Buttons (ALWAYS PINNED, HIGH VISIBILITY, GUARANTEED UNTRUNCATED) ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grid Toggle Icon Button
              Tooltip(
                message: _showGrid ? 'Tắt lưới 9 ô' : 'Bật lưới 9 ô',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _showGrid = !_showGrid),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _showGrid
                            ? const Color(0xFFFFD700).withAlpha(45)
                            : Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _showGrid ? const Color(0xFFFFD700) : Colors.white38,
                          width: 1.2,
                        ),
                        boxShadow: _showGrid
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withAlpha(90),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: Icon(
                        _showGrid ? Icons.grid_on : Icons.grid_off,
                        color: _showGrid ? const Color(0xFFFFD700) : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Camera Settings Icon Button
              Tooltip(
                message: 'Cài đặt camera',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _showSettings
                            ? const Color(0xFFFFD700).withAlpha(45)
                            : Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _showSettings ? const Color(0xFFFFD700) : Colors.white38,
                          width: 1.2,
                        ),
                        boxShadow: _showSettings
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withAlpha(90),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.tune,
                        color: _showSettings ? const Color(0xFFFFD700) : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Camera preview (aspect-ratio correct, pinch-zoom, stabilization & real-time filter matrix) ──
  Widget _buildCameraPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(_controller!);
    }

    final double sensorW = previewSize.height; // landscape width  → portrait height-axis
    final double sensorH = previewSize.width;  // landscape height → portrait width-axis

    Widget preview = OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: sensorW,
          height: sensorH,
          child: CameraPreview(_controller!),
        ),
      ),
    );

    // Apply action-camera motion dampening scale buffer when Super Steady is active
    if (_stabilizationMode == StabilizationMode.superSteady) {
      preview = Transform.scale(
        scale: 1.04,
        child: preview,
      );
    }

    // Apply real-time 60 FPS GPU color/beauty filter to live viewfinder
    final matrix = FilterHelper.getMatrix(_selectedFilter);
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

    // Apply horizontal mirror flip for front camera selfie preview
    if (_isFrontCamera && _mirrorFrontCamera) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
        child: preview,
      );
    }

    // Pinch to Zoom gesture
    return GestureDetector(
      onScaleStart: (details) {
        _baseScale = _currentZoom;
      },
      onScaleUpdate: (details) {
        final newZoom = (_baseScale * details.scale).clamp(_minAvailableZoom, _maxAvailableZoom);
        _setZoom(newZoom);
      },
      child: preview,
    );
  }

  // ── Preview area ──────────────────────────────────────────────────────────────
  Widget _buildPreviewArea() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: Text('Không thể khởi động camera.\nKiểm tra quyền truy cập.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70)),
      );
    }
    return Stack(children: [
      // ── Camera preview: fill screen, preserve sensor aspect ratio (no stretch) ──
      Positioned.fill(
        child: _buildCameraPreview(),
      ),

      // Lưới 9 ô (rule of thirds)
      if (_showGrid) _buildGridOverlay(),

      // Flash blink khi chụp
      if (_isTakingPhoto)
        Positioned.fill(child: Container(color: Colors.white.withAlpha(200))),

      // Countdown overlay
      if (_isPhotoCountingDown)
        Positioned.fill(
          child: Container(
            color: Colors.black.withAlpha(140),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$_photoCountdown',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 100,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 16)],
                    )),
                const SizedBox(height: 12),
                const Text('Chạm để huỷ',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ]),
            ),
          ),
        ),

      // Burst progress overlay
      if (_isBursting)
        Positioned(
          bottom: 16, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(200),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.burst_mode, color: Color(0xFFFFD700), size: 20),
                const SizedBox(width: 8),
                Text(
                  '$_burstProgress / $_burstTotal tấm',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]),
            ),
          ),
        ),

      // Burst badge (top-left) when burst mode is active but not shooting
      if (_burstCount > 0 && !_isBursting)
        Positioned(
          top: 10, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.burst_mode, size: 13, color: Colors.black87),
              const SizedBox(width: 4),
              Text(
                '$_burstCount tấm',
                style: const TextStyle(
                  color: Colors.black87, fontSize: 11,
                  fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ),

      // Badges: Stabilization + Filter + Quality + HDR (top-right)
      Positioned(
        top: 10, right: 10,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stabilizationMode != StabilizationMode.off) ...[
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _stabilizationMode == StabilizationMode.superSteady
                          ? Icons.motion_photos_auto
                          : Icons.motion_photos_on,
                      size: 11,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _stabilizationMode == StabilizationMode.superSteady ? 'STEADY' : 'OIS',
                      style: const TextStyle(
                        color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
            if (_selectedFilter != CameraFilter.none) ...[
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, size: 11, color: Colors.black),
                    const SizedBox(width: 3),
                    Text(
                      FilterHelper.getLabel(_selectedFilter),
                      style: const TextStyle(
                        color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ],
            if (_mode == CameraMode.photo && _hdrMode != HdrMode.off) ...[
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withAlpha(220),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Text(
                  _hdrMode == HdrMode.on ? 'HDR' : 'HDR AUTO',
                  style: const TextStyle(
                    color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700).withAlpha(120), width: 0.8),
              ),
              child: Text(
                _resolution == ResolutionPreset.veryHigh ? 'Full HD' : 'HD',
                style: const TextStyle(
                  color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),

      // ── Quick Filter Carousel Bar (above bottom controls) ──
      if (_showFilterBar)
        Positioned(
          bottom: 12,
          left: 12,
          right: 12,
          child: FilterCarouselBar(
            selected: _selectedFilter,
            onSelected: (filter) {
              setState(() => _selectedFilter = filter);
            },
          ),
        ),

      // Settings panel
      if (_showSettings) _buildSettingsPanel(),
    ]);
  }

  // ── Settings panel ────────────────────────────────────────────────────────────
  Widget _buildSettingsPanel() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF18181A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFF38383A), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 20,
              spreadRadius: 5,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar with title and close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 8),
                      Text(
                        'CÀI ĐẶT CAMERA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _showSettings = false),
                    tooltip: 'Đóng cài đặt',
                  ),
                ],
              ),
              const Divider(color: Color(0xFF333336), height: 22, thickness: 1),

              // Chống rung OIS / EIS / Super Steady
              StabilizationSelector(
                selected: _stabilizationMode,
                onChanged: (mode) {
                  setState(() => _stabilizationMode = mode);
                  _applyStabilization();
                },
              ),
              const SizedBox(height: 18),

              // Bộ lọc màu & Làm đẹp
              FilterSettingsSelector(
                selected: _selectedFilter,
                onChanged: (filter) => setState(() => _selectedFilter = filter),
              ),
              const SizedBox(height: 18),

              // Lưới 9 ô (Rule of thirds)
              _buildGridSettingsSelector(),
              const SizedBox(height: 18),

              // Lật ảnh (Mirror / Selfie Flip) — hiển thị cho cả 2 camera,
              // mặc định BẬT khi camera trước đang hoạt động
              _buildMirrorSettingsSelector(),
              const SizedBox(height: 18),

              QualitySelector(selected: _resolution, onChanged: _changeQuality),
              const SizedBox(height: 18),
              if (_mode == CameraMode.photo) ...[
                HdrSelector(
                  selected: _hdrMode,
                  onChanged: (v) => setState(() => _hdrMode = v),
                ),
                const SizedBox(height: 18),
                TimerSelector(
                  label: 'HẸN GIỜ CHỤP ẢNH',
                  icon: Icons.timer_outlined,
                  options: _photoTimerOptions,
                  selected: _selectedPhotoTimer,
                  onChanged: (v) => setState(() => _selectedPhotoTimer = v),
                ),
                const SizedBox(height: 18),
                _buildBurstSelector(),
                const SizedBox(height: 18),
                TimestampSelector(
                  enabled: _showTimestamp,
                  onChanged: (v) => setState(() => _showTimestamp = v),
                ),
              ] else ...[
                TimerSelector(
                  label: 'THỜI LƯỢNG QUAY TỰ ĐỘNG',
                  icon: Icons.videocam_outlined,
                  options: _videoDurationOptions,
                  selected: _selectedVideoDuration,
                  onChanged: (v) { if (!_isRecording) setState(() => _selectedVideoDuration = v); },
                ),
              ],
              const SizedBox(height: 18),
              StorageSelector(
                selected: _storageLocation,
                sdcardAvailable: _sdcardAvailable,
                onChanged: (loc) => setState(() => _storageLocation = loc),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom controls ────────────────────────────────────────────────────────────
  Widget _buildBottomControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 8, bottom: 26),
      child: Column(children: [
        // ── Zoom Selector (0.5x, 1x, 2x, 4x, 10x - Default 1x) ──
        ZoomSelector(
          currentZoom: _currentZoom,
          minZoom: _minAvailableZoom,
          maxZoom: _maxAvailableZoom,
          onZoomChanged: _setZoom,
        ),
        const SizedBox(height: 10),
        if (!_isRecording) _buildModeSelector(),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Thumbnail ảnh/video gần nhất
            GestureDetector(
              onTap: _lastSavedPath != null
                  ? () => _openPreview(_lastSavedPath!, _lastSavedIsVideo)
                  : null,
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: _lastSavedPath != null && !_lastSavedIsVideo
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.file(File(_lastSavedPath!), fit: BoxFit.cover),
                      )
                    : const Icon(Icons.photo_library_outlined, color: Colors.white38, size: 28),
              ),
            ),

            // Nút chụp / quay
            _buildShutterButton(),

            // Flip camera
            GestureDetector(
              onTap: _isRecording ? null : _switchCamera,
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(
                  Icons.flip_camera_android,
                  color: _isRecording ? Colors.white24 : Colors.white,
                  size: 26,
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _buildModeSelector() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _ModeButton(
        label: '📷  ẢNH',
        isSelected: _mode == CameraMode.photo,
        onTap: () => setState(() { _mode = CameraMode.photo; _showSettings = false; }),
      ),
      const SizedBox(width: 8),
      _ModeButton(
        label: '🎬  VIDEO',
        isSelected: _mode == CameraMode.video,
        onTap: () => setState(() { _mode = CameraMode.video; _showSettings = false; }),
      ),
    ]);
  }

  // ── Burst selector (inline widget) ────────────────────────────────────────────────
  Widget _buildBurstSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.burst_mode, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'CHỤP LIÊN TIẾP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _burstOptions.map((count) {
              final isSelected = _burstCount == count;
              final label = count == 0 ? 'Tắt' : '$count tấm';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _burstCount = count),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF48484A),
                        width: 1.2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withAlpha(80),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (count > 0) ...[
                          Icon(
                            Icons.burst_mode,
                            size: 14,
                            color: isSelected ? Colors.black87 : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildShutterButton() {
    if (_mode == CameraMode.photo) {
      return GestureDetector(
        onTap: _handleCapture,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isPhotoCountingDown ? Colors.orange : Colors.white,
            border: Border.all(color: const Color(0xFFFFD700), width: 3),
          ),
          child: Center(
            child: _isPhotoCountingDown
                ? Text('$_photoCountdown',
                    style: const TextStyle(
                      color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold))
                : _isBursting
                    ? const Icon(Icons.burst_mode, color: Color(0xFFFFD700), size: 32)
                    : _burstCount > 0
                        ? const Icon(Icons.burst_mode, color: Colors.black87, size: 32)
                        : const Icon(Icons.camera_alt, color: Colors.black87, size: 36),
          ),
        ),
      );
    } else {
      return GestureDetector(
        onTap: _handleVideoButton,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecording ? Colors.red : Colors.white,
            border: Border.all(
              color: _isRecording ? Colors.red.shade300 : const Color(0xFFFFD700),
              width: 3,
            ),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isRecording
                  ? const Icon(Icons.stop, key: ValueKey('stop'), color: Colors.white, size: 38)
                  : const Icon(Icons.videocam, key: ValueKey('rec'), color: Colors.black87, size: 36),
            ),
          ),
        ),
      );
    }
  }

  // ── Grid overlay ────────────────────────────────────────────────────────────
  /// Rule-of-thirds 3×3 grid with intersection highlight dots.
  Widget _buildGridOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(),
        ),
      ),
    );
  }

  // ── Grid Settings Selector ──────────────────────────────────────────────────
  Widget _buildGridSettingsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.grid_on, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'LƯỚI 9 Ô (RULE OF THIRDS)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _GridOption(
              icon: Icons.grid_on,
              label: 'Hiện lưới 9 ô',
              isSelected: _showGrid,
              onTap: () => setState(() => _showGrid = true),
            ),
            const SizedBox(width: 10),
            _GridOption(
              icon: Icons.grid_off,
              label: 'Tắt lưới',
              isSelected: !_showGrid,
              onTap: () => setState(() => _showGrid = false),
            ),
          ],
        ),
      ],
    );
  }

  // ── Mirror / Selfie Flip Settings Selector ────────────────────────────────────
  Widget _buildMirrorSettingsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flip, size: 16, color: Color(0xFFFFD700)),
            const SizedBox(width: 6),
            const Text(
              'LẬT ẢNH SELFIE (MIRROR)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            if (_isFrontCamera)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
                ),
                child: const Text(
                  'Camera trước',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _isFrontCamera
              ? 'Lật gương ảnh selfie. Mặc định BẬT khi dùng camera trước.'
              : 'Chỉ áp dụng khi chuyển sang camera trước.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _GridOption(
              icon: Icons.flip,
              label: 'Bật lật ảnh',
              isSelected: _mirrorFrontCamera,
              onTap: () => setState(() => _mirrorFrontCamera = true),
            ),
            const SizedBox(width: 10),
            _GridOption(
              icon: Icons.flip_outlined,
              label: 'Tắt lật ảnh',
              isSelected: !_mirrorFrontCamera,
              onTap: () => setState(() => _mirrorFrontCamera = false),
            ),
          ],
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(70)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFFFFD700).withAlpha(180)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // 2 vertical lines at 1/3 and 2/3
    for (int i = 1; i <= 2; i++) {
      final x = w * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
    }

    // 2 horizontal lines at 1/3 and 2/3
    for (int i = 1; i <= 2; i++) {
      final y = h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
    }

    // 4 intersection dots (power points)
    for (int col = 1; col <= 2; col++) {
      for (int row = 1; row <= 2; row++) {
        canvas.drawCircle(
          Offset(w * col / 3, h * row / 3),
          3.5,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// ── Mode button ────────────────────────────────────────────────────────────────
class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white24),
        ),
        child: Text(label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── Grid option button ─────────────────────────────────────────────────────────
class _GridOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GridOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF48484A),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withAlpha(80),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.black87 : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black87 : Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
