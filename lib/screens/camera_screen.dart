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
  bool _isTakingPhoto = false;
  String? _lastSavedPath;
  bool _lastSavedIsVideo = false;

  // ── Flash ────────────────────────────────────────────────────────────────────
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

  // ── Permissions ──────────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
      Permission.videos,
    ].request();

    final camOk = await Permission.camera.isGranted;
    final micOk = await Permission.microphone.isGranted;

    if (camOk && micOk) {
      _initCamera();
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

  // ── Flash ─────────────────────────────────────────────────────────────────────
  void _toggleFlash() {
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
    final next = modes[(modes.indexOf(_flashMode) + 1) % modes.length];
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

  // ── Duration helpers ──────────────────────────────────────────────────────────
  int _photoTimerSeconds(String s) =>
      {'3s': 3, '5s': 5, '10s': 10, '15s': 15}[s] ?? 0;

  int _videoDurationSeconds(String s) =>
      {'15s': 15, '30s': 30, '1 phút': 60, '3 phút': 180, '5 phút': 300, '10 phút': 600}[s] ?? 0;

  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ── Save directory ────────────────────────────────────────────────────────────
  Future<String> _getSaveDir(bool isVideo) async {
    Directory? dir;
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final root = ext.path.split('Android').first;
          dir = Directory(isVideo ? '${root}Movies/CameraApp' : '${root}Pictures/CameraApp');
        }
      } catch (_) {}
    }
    dir ??= await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  // ── Photo capture ─────────────────────────────────────────────────────────────
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
        setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
        _takePhoto();
      } else {
        setState(() => _photoCountdown--);
      }
    });
  }

  void _cancelPhotoCountdown() {
    _photoCountdownTimer?.cancel();
    setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTakingPhoto = true);
    try {
      final xFile = await _controller!.takePicture();
      final dir = await _getSaveDir(false);
      final filePath = path.join(dir, 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(xFile.path).copy(filePath);
      setState(() { _isTakingPhoto = false; _lastSavedPath = filePath; _lastSavedIsVideo = false; });
      if (mounted) {
        _showSnackbar('✅ Ảnh đã lưu', Colors.green);
        _openPreview(filePath, false);
      }
    } on CameraException catch (e) {
      setState(() => _isTakingPhoto = false);
      debugPrint('Take photo error: $e');
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
        _showSnackbar('✅ Video đã lưu', Colors.green);
        _openPreview(filePath, true);
      }
    } on CameraException catch (e) {
      WakelockPlus.disable();
      setState(() => _isRecording = false);
      debugPrint('Stop recording error: $e');
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(_flashIcon, color: Colors.white),
            onPressed: _mode == CameraMode.photo ? _toggleFlash : null,
            tooltip: 'Flash',
          ),
          if (_isRecording)
            Row(children: [
              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
              const SizedBox(width: 6),
              Text(
                _formatDuration(_recordingElapsed),
                style: const TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold, fontFamily: 'monospace',
                ),
              ),
              if (_selectedVideoDuration != 'Tắt')
                Text(' / $_selectedVideoDuration',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ])
          else
            const Text('Camera',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _showSettings ? const Color(0xFFFFD700) : Colors.white,
            ),
            onPressed: () => setState(() => _showSettings = !_showSettings),
            tooltip: 'Cài đặt',
          ),
        ],
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
      Positioned.fill(child: CameraPreview(_controller!)),

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

      // Settings panel
      if (_showSettings) _buildSettingsPanel(),

      // Badge chất lượng
      Positioned(
        top: 10, right: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(140),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _resolution == ResolutionPreset.veryHigh ? 'Full HD' : 'HD',
            style: const TextStyle(
              color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ]);
  }

  // ── Settings panel ────────────────────────────────────────────────────────────
  Widget _buildSettingsPanel() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(225),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white30,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            QualitySelector(selected: _resolution, onChanged: _changeQuality),
            const SizedBox(height: 20),
            if (_mode == CameraMode.photo) ...[
              TimerSelector(
                label: 'HẸN GIỜ CHỤP ẢNH',
                options: _photoTimerOptions,
                selected: _selectedPhotoTimer,
                onChanged: (v) => setState(() => _selectedPhotoTimer = v),
              ),
            ] else ...[
              TimerSelector(
                label: 'THỜI LƯỢNG QUAY TỰ ĐỘNG',
                options: _videoDurationOptions,
                selected: _selectedVideoDuration,
                onChanged: (v) { if (!_isRecording) setState(() => _selectedVideoDuration = v); },
              ),
            ],
            const SizedBox(height: 8),
          ],
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
