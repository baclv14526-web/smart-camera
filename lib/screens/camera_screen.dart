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
  bool _isTakingPhoto = false;
  String? _lastSavedPath;
  bool _lastSavedIsVideo = false;

  // ── Storage location ──────────────────────────────────────────────────────────
  StorageLocation _storageLocation = StorageLocation.phone;
  bool _sdcardAvailable = false;
  String? _sdcardAppPath;
  String? _sdcardRootPath;

  // ── Timestamp watermark ───────────────────────────────────────────────────────
  bool _showTimestamp = true;

  // ── HDR Mode ─────────────────────────────────────────────────────────────────
  HdrMode _hdrMode = HdrMode.auto;

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
      if (mounted) setState(() => _isInitializing = false);
    } on CameraException catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  // ── Switch camera ─────────────────────────────────────────────────────────────
  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
      _cameraIndex = _cameraIndex == 0 ? 1 : 0;
      _isInitializing = true;
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

  // ── Photo Post-Processing: HDR Low-Light & Timestamp ──────────────────────
  Future<void> _processCapturedPhoto(String sourcePath, String destPath) async {
    final applyHdr = _hdrMode == HdrMode.on || _hdrMode == HdrMode.auto;
    final applyTimestamp = _showTimestamp;

    if (!applyHdr && !applyTimestamp) {
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

      if (applyHdr) {
        // 1. Base image layer
        canvas.drawImage(image, Offset.zero, Paint());

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
      } else {
        canvas.drawImage(image, Offset.zero, Paint());
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
    try {
      final xFile = await _controller!.stopVideoRecording();
      WakelockPlus.disable();
      final dir = await _getSaveDir(true);
      final filePath = path.join(dir, 'VID_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await File(xFile.path).copy(filePath);
      setState(() { _isRecording = false; _recordingElapsed = 0; _lastSavedPath = filePath; _lastSavedIsVideo = true; });
      if (mounted) {
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        _showSnackbar('✅ Đã lưu video vào $locText', Colors.green);
        _openPreview(filePath, true);
      }
    } catch (e) {
      WakelockPlus.disable();
      setState(() => _isRecording = false);
      debugPrint('Stop recording error: $e');
      if (mounted) {
        _showSnackbar('❌ Lỗi khi lưu video: $e', Colors.red);
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Flash & HDR
          Row(
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          size: 15,
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
            ],
          ),

          // Center: Recording timer or Mode Title
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
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (_selectedVideoDuration != 'Tắt')
                    Text(
                      ' / $_selectedVideoDuration',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                ],
              ),
            )
          else
            Text(
              _mode == CameraMode.photo ? 'CHỤP ẢNH' : 'QUAY VIDEO',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),

          // Right: Grid & ALWAYS-VISIBLE Setting Button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grid Toggle
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  key: ValueKey(_showGrid),
                  icon: Icon(
                    _showGrid ? Icons.grid_on : Icons.grid_off,
                    color: _showGrid ? const Color(0xFFFFD700) : Colors.white,
                  ),
                  onPressed: () => setState(() => _showGrid = !_showGrid),
                  tooltip: _showGrid ? 'Tắt lưới 9 ô' : 'Bật lưới 9 ô',
                ),
              ),

              // Camera Settings Button (Always Visible & Prominent)
              Container(
                decoration: _showSettings
                    ? BoxDecoration(
                        color: const Color(0xFFFFD700).withAlpha(40),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
                      )
                    : null,
                child: IconButton(
                  icon: Icon(
                    Icons.tune,
                    color: _showSettings ? const Color(0xFFFFD700) : Colors.white,
                    size: 22,
                  ),
                  onPressed: () => setState(() => _showSettings = !_showSettings),
                  tooltip: 'Cài đặt camera',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Camera preview (aspect-ratio correct) ────────────────────────────────────
  /// Fills the available space while preserving the sensor's native aspect ratio.
  /// Uses FittedBox(cover) so the image is cropped at the edges rather than
  /// stretched — identical to how the stock Oppo camera renders the viewfinder.
  Widget _buildCameraPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(_controller!);
    }

    // previewSize.width is always the longer dimension regardless of orientation.
    // On a portrait device the sensor "width" maps to screen height, so we swap.
    final double sensorW = previewSize.height; // landscape width  → portrait height-axis
    final double sensorH = previewSize.width;  // landscape height → portrait width-axis

    return OverflowBox(
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

      // Badges: Quality + HDR (top-right)
      Positioned(
        top: 10, right: 10,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      padding: const EdgeInsets.only(top: 16, bottom: 28),
      child: Column(children: [
        if (!_isRecording) _buildModeSelector(),
        const SizedBox(height: 20),
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
