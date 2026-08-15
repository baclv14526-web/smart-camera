import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/timer_selector.dart';
import '../widgets/quality_selector.dart';
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
  // ── Camera controller ──────────────────────────────────────────────────────
  CameraController? _controller;
  int _cameraIndex = 0; // 0 = back, 1 = front
  ResolutionPreset _resolution = ResolutionPreset.veryHigh;

  // ── Mode ───────────────────────────────────────────────────────────────────
  CameraMode _mode = CameraMode.photo;

  // ── Photo timer ────────────────────────────────────────────────────────────
  final List<String> _photoTimerOptions = ['Tắt', '3s', '5s', '10s', '15s'];
  String _selectedPhotoTimer = 'Tắt';
  Timer? _photoCountdownTimer;
  int _photoCountdown = 0;
  bool _isPhotoCountingDown = false;

  // ── Video duration ─────────────────────────────────────────────────────────
  final List<String> _videoDurationOptions = [
    'Tắt',
    '15s',
    '30s',
    '1 phút',
    '3 phút',
    '5 phút',
    '10 phút',
  ];
  String _selectedVideoDuration = 'Tắt';

  // ── Video recording state ──────────────────────────────────────────────────
  bool _isRecording = false;
  int _recordingElapsed = 0; // seconds
  Timer? _recordingTimer;
  Timer? _autoStopTimer;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isInitializing = true;
  bool _showSettings = false;
  bool _isTakingPhoto = false;
  String? _lastSavedPath;

  // ── Flash ──────────────────────────────────────────────────────────────────
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
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

  // ── Permissions ─────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();

    final cameraOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    if (cameraOk && micOk) {
      _initCamera();
    } else {
      setState(() => _isInitializing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cần cấp quyền Camera và Microphone để sử dụng'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Camera init ─────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    await _controller?.dispose();

    final camera = widget.cameras[_cameraIndex];
    final controller = CameraController(
      camera,
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

  // ── Switch camera ───────────────────────────────────────────────────────────
  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
      _cameraIndex = _cameraIndex == 0 ? 1 : 0;
      _isInitializing = true;
    });
    await _initCamera();
  }

  // ── Flash ────────────────────────────────────────────────────────────────────
  void _toggleFlash() {
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final idx = modes.indexOf(_flashMode);
    final next = modes[(idx + 1) % modes.length];
    setState(() => _flashMode = next);
    _controller?.setFlashMode(next);
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  // ── Parse durations ─────────────────────────────────────────────────────────
  int _photoTimerSeconds(String s) {
    switch (s) {
      case '3s':
        return 3;
      case '5s':
        return 5;
      case '10s':
        return 10;
      case '15s':
        return 15;
      default:
        return 0;
    }
  }

  int _videoDurationSeconds(String s) {
    switch (s) {
      case '15s':
        return 15;
      case '30s':
        return 30;
      case '1 phút':
        return 60;
      case '3 phút':
        return 180;
      case '5 phút':
        return 300;
      case '10 phút':
        return 600;
      default:
        return 0;
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Save directory ──────────────────────────────────────────────────────────
  Future<String> _getSaveDirectory(bool isVideo) async {
    Directory? dir;

    if (Platform.isAndroid) {
      // Try Pictures/CameraApp on SD card first
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          // Navigate up to root and go to Pictures
          final root = external.path.split('Android').first;
          final folder = isVideo
              ? '${root}Movies/CameraApp'
              : '${root}Pictures/CameraApp';
          dir = Directory(folder);
        }
      } catch (_) {}
    }

    dir ??= await getApplicationDocumentsDirectory();

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  // ── Photo capture ───────────────────────────────────────────────────────────
  Future<void> _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isPhotoCountingDown) {
      _cancelPhotoCountdown();
      return;
    }

    final delay = _photoTimerSeconds(_selectedPhotoTimer);
    if (delay == 0) {
      await _takePhoto();
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
        setState(() {
          _photoCountdown = 0;
          _isPhotoCountingDown = false;
        });
        _takePhoto();
      } else {
        setState(() => _photoCountdown--);
      }
    });
  }

  void _cancelPhotoCountdown() {
    _photoCountdownTimer?.cancel();
    setState(() {
      _photoCountdown = 0;
      _isPhotoCountingDown = false;
    });
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTakingPhoto = true);

    try {
      final xFile = await _controller!.takePicture();
      final dir = await _getSaveDirectory(false);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = path.join(dir, 'IMG_$ts.jpg');
      await File(xFile.path).copy(filePath);

      setState(() {
        _isTakingPhoto = false;
        _lastSavedPath = filePath;
      });

      if (mounted) {
        _showSavedSnackbar('Ảnh đã lưu');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PreviewScreen(filePath: filePath, isVideo: false),
          ),
        );
      }
    } on CameraException catch (e) {
      setState(() => _isTakingPhoto = false);
      debugPrint('Take photo error: $e');
    }
  }

  // ── Video recording ─────────────────────────────────────────────────────────
  Future<void> _handleVideoButton() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.startVideoRecording();
      WakelockPlus.enable();

      setState(() {
        _isRecording = true;
        _recordingElapsed = 0;
      });

      // Elapsed timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _recordingElapsed++);
      });

      // Auto-stop timer
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

      final dir = await _getSaveDirectory(true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = path.join(dir, 'VID_$ts.mp4');
      await File(xFile.path).copy(filePath);

      setState(() {
        _isRecording = false;
        _recordingElapsed = 0;
        _lastSavedPath = filePath;
      });

      if (mounted) {
        _showSavedSnackbar('Video đã lưu');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PreviewScreen(filePath: filePath, isVideo: true),
          ),
        );
      }
    } on CameraException catch (e) {
      WakelockPlus.disable();
      setState(() => _isRecording = false);
      debugPrint('Stop recording error: $e');
    }
  }

  void _showSavedSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Change quality ──────────────────────────────────────────────────────────
  Future<void> _changeQuality(ResolutionPreset preset) async {
    if (_isRecording) return;
    setState(() {
      _resolution = preset;
      _isInitializing = true;
    });
    await _initCamera();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCameraPreview()),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flash
          IconButton(
            icon: Icon(_flashIcon, color: Colors.white, size: 26),
            onPressed: _toggleFlash,
          ),

          // Recording indicator / title
          if (_isRecording)
            Row(
              children: [
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                Text(
                  _formatDuration(_recordingElapsed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                if (_selectedVideoDuration != 'Tắt') ...[
                  const Text(' / ',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                  Text(
                    _selectedVideoDuration,
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ],
            )
          else
            const Text(
              'Camera',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

          // Settings
          IconButton(
            icon: Icon(
              _showSettings ? Icons.settings : Icons.tune,
              color: _showSettings ? const Color(0xFFFFD700) : Colors.white,
              size: 26,
            ),
            onPressed: () => setState(() => _showSettings = !_showSettings),
          ),
        ],
      ),
    );
  }

  // ── Camera preview area ─────────────────────────────────────────────────────
  Widget _buildCameraPreview() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: Text(
          'Không thể khởi động camera.\nKiểm tra lại quyền truy cập.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Stack(
      children: [
        // Preview
        Positioned.fill(
          child: ClipRRect(
            child: CameraPreview(_controller!),
          ),
        ),

        // Flash overlay on capture
        if (_isTakingPhoto)
          Positioned.fill(
            child: Container(color: Colors.white.withOpacity(0.8)),
          ),

        // Countdown overlay
        if (_isPhotoCountingDown)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_photoCountdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 96,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Chạm để huỷ',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Settings panel
        if (_showSettings) _buildSettingsPanel(),

        // Resolution badge
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _resolution == ResolutionPreset.veryHigh ? 'Full HD' : 'HD',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Settings panel ──────────────────────────────────────────────────────────
  Widget _buildSettingsPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.88),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Quality
            QualitySelector(
              selected: _resolution,
              onChanged: _changeQuality,
            ),
            const SizedBox(height: 20),

            // Photo timer (only in photo mode)
            if (_mode == CameraMode.photo) ...[
              TimerSelector(
                label: 'HẸN GIỜ CHỤP ẢNH',
                options: _photoTimerOptions,
                selected: _selectedPhotoTimer,
                onChanged: (v) => setState(() => _selectedPhotoTimer = v),
              ),
              const SizedBox(height: 20),
            ],

            // Video duration (only in video mode)
            if (_mode == CameraMode.video) ...[
              TimerSelector(
                label: 'THỜI LƯỢNG QUAY TỰ ĐỘNG',
                options: _videoDurationOptions,
                selected: _selectedVideoDuration,
                onChanged: (v) {
                  if (!_isRecording) {
                    setState(() => _selectedVideoDuration = v);
                  }
                },
              ),
              const SizedBox(height: 20),
            ],

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // ── Bottom controls ─────────────────────────────────────────────────────────
  Widget _buildBottomControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(bottom: 24, top: 16),
      child: Column(
        children: [
          // Mode selector
          if (!_isRecording) _buildModeSelector(),
          const SizedBox(height: 20),

          // Main controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Last saved thumbnail / empty
              GestureDetector(
                onTap: _lastSavedPath != null
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PreviewScreen(
                              filePath: _lastSavedPath!,
                              isVideo: _mode == CameraMode.video,
                            ),
                          ),
                        )
                    : null,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: _lastSavedPath != null &&
                          _mode == CameraMode.photo
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Image.file(
                            File(_lastSavedPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white38,
                          size: 28,
                        ),
                ),
              ),

              // Shutter button
              _buildShutterButton(),

              // Flip camera
              GestureDetector(
                onTap: _switchCamera,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.flip_camera_android,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeButton(
          label: '📷  ẢNH',
          isSelected: _mode == CameraMode.photo,
          onTap: () => setState(() {
            _mode = CameraMode.photo;
            _showSettings = false;
          }),
        ),
        const SizedBox(width: 8),
        _ModeButton(
          label: '🎬  VIDEO',
          isSelected: _mode == CameraMode.video,
          onTap: () => setState(() {
            _mode = CameraMode.video;
            _showSettings = false;
          }),
        ),
      ],
    );
  }

  Widget _buildShutterButton() {
    if (_mode == CameraMode.photo) {
      // Photo shutter
      return GestureDetector(
        onTap: _handleCapture,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isPhotoCountingDown
                ? Colors.orange
                : (_isTakingPhoto ? Colors.grey : Colors.white),
            border: Border.all(
              color: const Color(0xFFFFD700),
              width: 3,
            ),
          ),
          child: _isPhotoCountingDown
              ? Center(
                  child: Text(
                    '$_photoCountdown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.camera_alt,
                    color: Colors.black87,
                    size: 34,
                  ),
                ),
        ),
      );
    } else {
      // Video record button
      return GestureDetector(
        onTap: _handleVideoButton,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 78,
          height: 78,
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
                  ? const Icon(
                      Icons.stop,
                      key: ValueKey('stop'),
                      color: Colors.white,
                      size: 36,
                    )
                  : const Icon(
                      Icons.videocam,
                      key: ValueKey('rec'),
                      color: Colors.black87,
                      size: 34,
                    ),
            ),
          ),
        ),
      );
    }
  }
}

// ── Helper widget ─────────────────────────────────────────────────────────────
class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFD700)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white24,
          ),
        ),
        child: Text(
          label,
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
