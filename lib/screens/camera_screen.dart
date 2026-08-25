// Import các thư viện cần thiết
import 'dart:async'; // Xử lý async/await và Timer
import 'dart:io'; // Xử lý file và directory
import 'dart:ui' as ui; // Xử lý ảnh và canvas
import 'package:flutter/material.dart'; // UI Flutter
import 'package:camera/camera.dart'; // Camera Flutter
import 'package:path_provider/path_provider.dart'; // Lấy đường dẫn thư mục hệ thống
import 'package:path/path.dart' as path; // Xử lý đường dẫn file
import 'package:permission_handler/permission_handler.dart'; // Yêu cầu quyền truy cập
import 'package:wakelock_plus/wakelock_plus.dart'; // Giữ màn hình không tắt
import '../widgets/timer_selector.dart'; // Widget chọn timer
import '../widgets/quality_selector.dart'; // Widget chọn chất lượng
import '../widgets/storage_selector.dart'; // Widget chọn bộ nhớ
import '../widgets/timestamp_selector.dart'; // Widget chọn timestamp
import '../widgets/hdr_selector.dart'; // Widget chọn HDR
import '../widgets/filter_selector.dart'; // Widget chọn filter
import '../widgets/stabilization_selector.dart'; // Widget chọn chống rung
import '../widgets/zoom_selector.dart'; // Widget chọn zoom
import 'preview_screen.dart'; // Màn hình xem ảnh/video

// Enum chế độ camera: chụp ảnh hoặc quay video
enum CameraMode { photo, video }

// Widget chính của màn hình camera
class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras; // Danh sách camera có sẵn trên thiết bị
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// State của màn hình camera, theo dõi lifecycle của app
class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Controller & Camera ──────────────────────────────────────────────────────────────
  CameraController? _controller; // Controller điều khiển camera
  int _cameraIndex = 0; // Index của camera đang dùng (0: sau, 1: trước)
  ResolutionPreset _resolution = ResolutionPreset.veryHigh; // Chất lượng camera

  // ── Chế độ hoạt động ────────────────────────────────────────────────────────────────────
  CameraMode _mode = CameraMode.photo; // Chế độ: chụp ảnh hoặc quay video

  // ── Zoom (0.5x, 1x, 2x, 4x, 10x - Mặc định 1x) ──────────────────────────────
  double _currentZoom = 1.0; // Mức zoom hiện tại
  double _minAvailableZoom = 1.0; // Zoom tối thiểu do hardware hỗ trợ
  double _maxAvailableZoom = 10.0; // Zoom tối đa (giới hạn ở 10x)
  double _baseScale = 1.0; // Scale cơ bản cho gesture pinch zoom

  // ── Timer chụp ảnh ─────────────────────────────────────────────────────────────
  final List<String> _photoTimerOptions = ['Tắt', '3s', '5s', '10s', '15s']; // Các tùy chọn timer
  String _selectedPhotoTimer = 'Tắt'; // Timer đang chọn
  Timer? _photoCountdownTimer; // Timer đếm ngược
  int _photoCountdown = 0; // Số giây đếm ngược
  bool _isPhotoCountingDown = false; // Đang đếm ngược hay không

  // ── Chụp liên tiếp (Burst mode) ──────────────────────────────────────────────
  final List<int> _burstOptions = [0, 3, 5, 7, 9, 15]; // Số tấm chụp liên tiếp (0 = tắt)
  int _burstCount = 0; // Số tấm đã chọn (0 = tắt)
  bool _isBursting = false; // Đang chụp liên tiếp hay không
  int _burstProgress = 0; // Số tấm đã chụp trong burst hiện tại
  int _burstTotal = 0;    // Tổng số tấm cần chụp trong burst hiện tại

  // ── Thời lượng quay video ───────────────────────────────────────────────────────────
  final List<String> _videoDurationOptions = [
    'Tắt', '15s', '30s', '1 phút', '3 phút', '5 phút', '10 phút',
  ];
  String _selectedVideoDuration = 'Tắt'; // Thời lượng tự động dừng quay

  // ── Trạng thái quay video ──────────────────────────────────────────────────────────
  bool _isRecording = false; // Đang quay video hay không
  int _recordingElapsed = 0; // Số giây đã quay
  Timer? _recordingTimer; // Timer đếm thời gian quay
  Timer? _autoStopTimer; // Timer tự động dừng quay

  // ── Trạng thái UI ─────────────────────────────────────────────────────────────────
  bool _isInitializing = true; // Đang khởi tạo camera hay không
  bool _showSettings = false; // Hiển thị panel cài đặt hay không
  bool _showGrid = false; // Hiển thị lưới 9 ô hay không
  bool _showFilterBar = false; // Hiển thị thanh filter hay không
  bool _isTakingPhoto = false; // Đang chụp ảnh hay không
  String? _lastSavedPath; // Đường dẫn file ảnh/video gần nhất
  bool _lastSavedIsVideo = false; // File gần nhất là video hay ảnh

  // ── Filter màu & Làm đẹp ───────────────────────────────────────────────────
  CameraFilter _selectedFilter = CameraFilter.none; // Filter đang chọn

  // ── Chống rung (OIS / EIS / Super Steady) ───────────────────────────
  StabilizationMode _stabilizationMode = StabilizationMode.standard; // Chế độ chống rung

  // ── Vị trí lưu file ──────────────────────────────────────────────────────────
  StorageLocation _storageLocation = StorageLocation.phone; // Lưu vào điện thoại hay SD card
  bool _sdcardAvailable = false; // Có thẻ SD hay không
  String? _sdcardAppPath; // Đường dẫn app trên SD card
  String? _sdcardRootPath; // Đường dẫn gốc SD card

  // ── Timestamp watermark ───────────────────────────────────────────────────────
  bool _showTimestamp = true; // Hiển thị timestamp trên ảnh hay không

  // ── Chế độ HDR ─────────────────────────────────────────────────────────────────
  HdrMode _hdrMode = HdrMode.auto; // Chế độ HDR (tắt, bật, auto)

  // ── Lật ảnh selfie (camera trước) ─────────────────────────────────────
  /// Lật ảnh ngang khi dùng camera trước. Mặc định bật khi chụp bằng camera trước.
  bool _mirrorFrontCamera = true;

  // Helper: Kiểm tra camera hiện tại có phải camera trước (selfie) không?
  bool get _isFrontCamera =>
      widget.cameras.isNotEmpty &&
      _cameraIndex < widget.cameras.length &&
      widget.cameras[_cameraIndex].lensDirection == CameraLensDirection.front;

  // ── Flash ────────────────────────────────────────────────────────────────────
  FlashMode _flashMode = FlashMode.off; // Chế độ flash (tắt, auto, luôn, torch)

  // ── Lifecycle methods ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Đăng ký observer để theo dõi lifecycle
    _requestPermissions(); // Yêu cầu quyền truy cập camera, microphone, storage
    _detectSdCard(); // Phát hiện thẻ SD card
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Hủy đăng ký observer
    _photoCountdownTimer?.cancel(); // Hủy timer đếm ngược
    _recordingTimer?.cancel(); // Hủy timer đếm thời gian quay
    _autoStopTimer?.cancel(); // Hủy timer tự động dừng
    _controller?.dispose(); // Giải phóng camera controller
    WakelockPlus.disable(); // Tắt chế độ giữ màn hình
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Xử lý khi app chuyển trạng thái (background/foreground)
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose(); // Khi app vào background, giải phóng camera
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(); // Khi app trở lại foreground, khởi tạo lại camera
    }
  }

  // ── Phát hiện thẻ SD Card ────────────────────────────────────────────────────────
  /// Quét các đường dẫn mount để tìm thẻ SD card vật lý
  Future<void> _detectSdCard() async {
    if (!Platform.isAndroid) return; // Chỉ Android mới có SD card
    try {
      final sdRoots = <String>{}; // Set lưu các đường dẫn SD card tìm được

      // 1. Quét trực tiếp thư mục /storage (tìm thẻ SD vật lý thật)
      try {
        final storageDir = Directory('/storage');
        if (storageDir.existsSync()) {
          for (final entity in storageDir.listSync()) {
            if (entity is Directory) {
              final name = path.basename(entity.path);
              // Loại trừ các đường dẫn ảo (emulated, self, knox, container)
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
            // Chỉ lấy thư mục không nằm trong /emulated/0 (bộ nhớ trong)
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
          final sdDir = rawDirs[1]; // Thư mục thứ 2 thường là SD card
          _sdcardAppPath ??= sdDir.path;
          final root = sdDir.path.split('Android').first;
          if (root.isNotEmpty) {
            sdRoots.add(root.endsWith('/') ? root.substring(0, root.length - 1) : root);
          }
        }
      } catch (_) {}

      // Nếu tìm thấy SD card
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

    // Không tìm thấy SD card
    setState(() {
      _sdcardAvailable = false;
      _sdcardAppPath = null;
      _sdcardRootPath = null;
      // Nếu trước đó đang chọn SD card, chuyển về bộ nhớ trong
      if (_storageLocation == StorageLocation.sdcard) {
        _storageLocation = StorageLocation.phone;
      }
    });
  }

  // ── Yêu cầu quyền truy cập ──────────────────────────────────────────────────────────────
  /// Yêu cầu các quyền cần thiết: camera, microphone, storage, photos, videos, manage external storage
  Future<void> _requestPermissions() async {
    await [
      Permission.camera, // Quyền camera
      Permission.microphone, // Quyền microphone (cho video)
      Permission.storage, // Quyền truy cập storage
      Permission.photos, // Quyền truy cập ảnh
      Permission.videos, // Quyền truy cập video
      Permission.manageExternalStorage, // Quyền quản lý storage bên ngoài (Android 11+)
    ].request();

    final camOk = await Permission.camera.isGranted;
    final micOk = await Permission.microphone.isGranted;

    if (camOk && micOk) {
      _initCamera(); // Nếu có đủ quyền, khởi tạo camera
      _detectSdCard(); // Phát hiện SD card
    } else {
      setState(() => _isInitializing = false);
      if (mounted) {
        _showSnackbar('Cần cấp quyền Camera và Microphone', Colors.red);
      }
    }
  }

  // ── Khởi tạo camera ───────────────────────────────────────────────────────────────
  /// Khởi tạo camera controller với các thông số và khả năng zoom
  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _isInitializing = false);
      return;
    }
    await _controller?.dispose(); // Giải phóng controller cũ nếu có

    final controller = CameraController(
      widget.cameras[_cameraIndex], // Camera đang chọn
      _resolution, // Chất lượng video/ảnh
      enableAudio: true, // Bật âm thanh cho video
      imageFormatGroup: ImageFormatGroup.jpeg, // Định dạng ảnh JPEG
    );
    _controller = controller;

    try {
      await controller.initialize(); // Khởi tạo camera
      await controller.setFlashMode(_flashMode); // Đặt chế độ flash

      // Query khả năng zoom của hardware (Mặc định 1x)
      try {
        final minZ = await controller.getMinZoomLevel(); // Zoom tối thiểu hardware
        final maxZ = await controller.getMaxZoomLevel(); // Zoom tối đa hardware
        _minAvailableZoom = minZ;
        _maxAvailableZoom = maxZ.clamp(1.0, 10.0); // Giới hạn tối đa 10x
        _currentZoom = 1.0.clamp(minZ, _maxAvailableZoom); // Reset về 1x
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

  // ── Đặt mức zoom (0.5x, 1x, 2x, 4x, 10x) ──────────────────────────────────
  /// Thay đổi mức zoom, clamp trong khoảng cho phép
  Future<void> _setZoom(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final targetZoom = zoom.clamp(_minAvailableZoom, _maxAvailableZoom); // Giới hạn zoom
    setState(() => _currentZoom = zoom);
    try {
      await _controller!.setZoomLevel(targetZoom); // Áp dụng zoom
    } catch (e) {
      debugPrint('Set zoom error: $e');
    }
  }

  // ── Chuyển camera (trước/sau) ─────────────────────────────────────────────────────────────
  /// Chuyển giữa camera sau và camera trước
  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return; // Cần ít nhất 2 camera
    final nextIndex = _cameraIndex == 0 ? 1 : 0; // Toggle index
    final nextIsFront = nextIndex < widget.cameras.length &&
        widget.cameras[nextIndex].lensDirection == CameraLensDirection.front;
    setState(() {
      _cameraIndex = nextIndex;
      _isInitializing = true;
      // Tự động bật lật ảnh khi chuyển sang camera trước
      if (nextIsFront) _mirrorFrontCamera = true;
    });
    await _initCamera(); // Khởi tạo lại camera mới
  }

  // ── Chuyển chế độ HDR ────────────────────────────────────────────────────────
  /// Toggle giữa 3 chế độ: Auto → On → Off → Auto
  void _cycleHdrMode() {
    setState(() {
      switch (_hdrMode) {
        case HdrMode.auto:
          _hdrMode = HdrMode.on; // Chuyển sang HDR bật
          break;
        case HdrMode.on:
          _hdrMode = HdrMode.off; // Chuyển sang HDR tắt
          break;
        case HdrMode.off:
          _hdrMode = HdrMode.auto; // Chuyển sang HDR auto
          break;
      }
    });
  }

  // ── Chuyển chế độ chống rung (OIS / EIS / Super Steady) ─────────────────────────
  /// Toggle giữa 3 chế độ: Off → Standard → Super Steady → Off
  void _cycleStabilizationMode() {
    setState(() {
      switch (_stabilizationMode) {
        case StabilizationMode.off:
          _stabilizationMode = StabilizationMode.standard; // Bật OIS chuẩn
          break;
        case StabilizationMode.standard:
          _stabilizationMode = StabilizationMode.superSteady; // Bật Super Steady
          break;
        case StabilizationMode.superSteady:
          _stabilizationMode = StabilizationMode.off; // Tắt chống rung
          break;
      }
    });
    _applyStabilization(); // Áp dụng chế độ mới
  }

  /// Áp dụng chế độ chống rung lên camera
  Future<void> _applyStabilization() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_stabilizationMode != StabilizationMode.off) {
        await _controller!.setFocusMode(FocusMode.auto); // Tự động lấy nét
        await _controller!.setExposureMode(ExposureMode.auto); // Tự động phơi sáng
      }
    } catch (e) {
      debugPrint('Stabilization apply error: $e');
    }
  }

  // ── Chuyển chế độ Flash ─────────────────────────────────────────────────────────────
  /// Toggle flash: chụp ảnh (off → auto → always), video (off → torch)
  void _toggleFlash() {
    if (_mode == CameraMode.photo) {
      // Chế độ chụp ảnh: Tắt → Auto → Luôn bật → Tắt
      final modes = [FlashMode.off, FlashMode.auto, FlashMode.always];
      final next = modes[(modes.indexOf(_flashMode) + 1) % modes.length];
      setState(() => _flashMode = next);
      _controller?.setFlashMode(next);
    } else {
      // Chế độ video: Tắt → Torch (đèn pin) → Tắt
      final next = _flashMode == FlashMode.torch || _flashMode == FlashMode.always
          ? FlashMode.off
          : FlashMode.torch;
      setState(() => _flashMode = next);
      _controller?.setFlashMode(next);
    }
  }

  /// Lấy icon tương ứng với chế độ flash hiện tại
  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on; // Icon flash bật
      case FlashMode.auto:
        return Icons.flash_auto; // Icon flash auto
      default:
        return Icons.flash_off; // Icon flash tắt
    }
  }

  // ── Helper chuyển đổi thời gian ──────────────────────────────────────────────────────────
  /// Chuyển chuỗi timer thành số giây
  int _photoTimerSeconds(String s) =>
      {'3s': 3, '5s': 5, '10s': 10, '15s': 15}[s] ?? 0;

  /// Chuyển chuỗi thời lượng video thành số giây
  int _videoDurationSeconds(String s) =>
      {'15s': 15, '30s': 30, '1 phút': 60, '3 phút': 180, '5 phút': 300, '10 phút': 600}[s] ?? 0;

  /// Format số giây thành dạng MM:SS
  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ── Lấy thư mục lưu file ────────────────────────────────────────────────────────────
  /// Tìm và xác thực thư mục có thể ghi file (ưu tiên SD card nếu được chọn)
  Future<String> _getSaveDir(bool isVideo) async {
    const appFolder = 'CameraApp2026'; // Tên thư mục app
    final mediaTypeFolder = isVideo ? 'Movies' : 'Pictures'; // Thư mục theo loại media

    if (Platform.isAndroid) {
      // ── 1. Nếu chọn thẻ SD Card ──
      if (_storageLocation == StorageLocation.sdcard) {
        final sdCandidates = <String>[];

        // Thư mục công khai trên SD Card (DCIM / Pictures / Movies / CameraApp2026)
        if (_sdcardRootPath != null) {
          sdCandidates.add(path.join(_sdcardRootPath!, 'DCIM', appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, mediaTypeFolder, appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, appFolder));
        }

        // Thư mục app-specific trên SD Card (đảm bảo quyền ghi trên Android 10+)
        if (_sdcardAppPath != null) {
          sdCandidates.add(path.join(_sdcardAppPath!, appFolder));
          sdCandidates.add(path.join(_sdcardAppPath!, mediaTypeFolder, appFolder));
          sdCandidates.add(_sdcardAppPath!);
        }

        // Đường dẫn package-specific trên SD
        if (_sdcardRootPath != null) {
          sdCandidates.add(path.join(_sdcardRootPath!, 'Android', 'data', 'com.example.camera_app', 'files', appFolder));
          sdCandidates.add(path.join(_sdcardRootPath!, 'Android', 'media', 'com.example.camera_app', appFolder));
        }

        // Test từng đường dẫn xem có thể ghi được không
        for (final candidate in sdCandidates) {
          try {
            final dir = Directory(candidate);
            if (!dir.existsSync()) {
              dir.createSync(recursive: true); // Tạo thư mục nếu chưa có
            }
            // Test ghi file
            final testFile = File(path.join(dir.path, '.test_${DateTime.now().millisecondsSinceEpoch}'));
            testFile.writeAsStringSync('ok');
            if (testFile.existsSync()) {
              testFile.deleteSync(); // Xóa file test
            }
            debugPrint('Valid writable SD card directory: ${dir.path}');
            return dir.path; // Trả về đường dẫn hợp lệ đầu tiên
          } catch (e) {
            debugPrint('SD write candidate $candidate rejected: $e');
          }
        }
        debugPrint('SD card write candidates rejected, falling back to phone storage');
      }

      // ── 2. Bộ nhớ trong điện thoại ──
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

      // Test từng đường dẫn bộ nhớ trong
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

    // ── 3. Fallback: Thư mục Documents của App ──
    final appDocDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(path.join(appDocDir.path, appFolder));
    if (!fallbackDir.existsSync()) {
      fallbackDir.createSync(recursive: true);
    }
    return fallbackDir.path;
  }

  // ── Xử lý chụp ảnh ─────────────────────────────────────────────────────────────
  /// Xử lý khi người dùng nhấn nút chụp: timer, burst, hoặc chụp đơn
  Future<void> _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isBursting) return; // Bỏ qua nếu đang chụp liên tiếp
    if (_isPhotoCountingDown) {
      _cancelPhotoCountdown(); // Hủy đếm ngược nếu đang chạy
      return;
    }
    final delay = _photoTimerSeconds(_selectedPhotoTimer); // Lấy thời gian timer
    if (delay == 0) {
      // Không có timer
      if (_burstCount > 0) {
        await _takeBurstPhotos(_burstCount); // Chụp liên tiếp
      } else {
        await _takePhoto(); // Chụp đơn
      }
    } else {
      _startPhotoCountdown(delay); // Bắt đầu đếm ngược
    }
  }

  /// Bắt đầu đếm ngược trước khi chụp
  void _startPhotoCountdown(int seconds) {
    setState(() {
      _photoCountdown = seconds;
      _isPhotoCountingDown = true;
    });
    _photoCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_photoCountdown <= 1) {
        t.cancel();
        setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
        // Đếm ngược xong, thực hiện chụp
        if (_burstCount > 0) {
          _takeBurstPhotos(_burstCount);
        } else {
          _takePhoto();
        }
      } else {
        setState(() => _photoCountdown--); // Giảm đếm
      }
    });
  }

  /// Hủy đếm ngược
  void _cancelPhotoCountdown() {
    _photoCountdownTimer?.cancel();
    setState(() { _photoCountdown = 0; _isPhotoCountingDown = false; });
  }

  // ── Xử lý ảnh sau chụp: Filter, HDR, Timestamp & Lật ảnh ─
  /// Áp dụng các hiệu ứng: filter màu, HDR, timestamp watermark, và lật ảnh selfie
  Future<void> _processCapturedPhoto(String sourcePath, String destPath) async {
    final applyHdr = _hdrMode == HdrMode.on || _hdrMode == HdrMode.auto; // Có bật HDR không
    final applyTimestamp = _showTimestamp; // Có hiển thị timestamp không
    final filterMatrix = FilterHelper.getMatrix(_selectedFilter); // Matrix filter màu
    final applyFilter = filterMatrix != null; // Có filter nào được chọn không
    // Lật ảnh: áp dụng khi camera trước VÀ setting lật ảnh được bật
    final applyMirror = _isFrontCamera && _mirrorFrontCamera;

    // Nếu không có hiệu ứng nào, chỉ copy file
    if (!applyHdr && !applyTimestamp && !applyFilter && !applyMirror) {
      await File(sourcePath).copy(destPath);
      return;
    }

    try {
      final bytes = await File(sourcePath).readAsBytes(); // Đọc file ảnh
      final codec = await ui.instantiateImageCodec(bytes); // Decode ảnh
      final frame = await codec.getNextFrame(); // Lấy frame đầu tiên
      final image = frame.image; // Lấy image object

      final recorder = ui.PictureRecorder(); // Recorder để vẽ lại
      final canvas = Canvas(recorder); // Canvas để vẽ

      // Áp dụng lật ngang cho ảnh selfie camera trước
      if (applyMirror) {
        canvas.save();
        canvas.translate(image.width.toDouble(), 0); // Dịch sang phải
        canvas.scale(-1.0, 1.0); // Lật ngang
      }

      // 1. Layer ảnh gốc (với filter màu/beauty nếu được chọn)
      final basePaint = Paint();
      if (applyFilter) {
        basePaint.colorFilter = ColorFilter.matrix(filterMatrix); // Áp dụng filter
      }
      canvas.drawImage(image, Offset.zero, basePaint); // Vẽ ảnh gốc

      if (applyHdr) {
        // 2. Layer HDR Shadow Recovery (Screen blend + sáng vùng tối)
        final hdrShadowPaint = Paint()
          ..blendMode = BlendMode.screen // Blend mode screen
          ..colorFilter = const ColorFilter.matrix(<double>[
            0.30, 0.0, 0.0, 0.0, 18, // Red channel
            0.0, 0.30, 0.0, 0.0, 18, // Green channel
            0.0, 0.0, 0.30, 0.0, 18, // Blue channel
            0.0, 0.0, 0.0, 1.0, 0,   // Alpha
          ]);
        canvas.drawImage(image, Offset.zero, hdrShadowPaint); // Vẽ layer shadow

        // 3. Layer tăng độ tương phản & độ rực màu (SoftLight blend)
        final hdrVibrancePaint = Paint()
          ..blendMode = BlendMode.softLight // Blend mode soft light
          ..colorFilter = const ColorFilter.matrix(<double>[
            1.10, 0.0, 0.0, 0.0, 0, // Tăng 10% độ rực
            0.0, 1.10, 0.0, 0.0, 0,
            0.0, 0.0, 1.10, 0.0, 0,
            0.0, 0.0, 0.0, 1.0, 0,
          ]);
        canvas.drawImage(image, Offset.zero, hdrVibrancePaint); // Vẽ layer vibrance
      }

      // Khôi phục transform canvas sau khi lật
      if (applyMirror) {
        canvas.restore();
      }

      // 4. Timestamp Watermark (nếu được bật)
      if (applyTimestamp) {
        final now = DateTime.now();
        final dateStr =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final fontSize = (image.width * 0.026).clamp(24.0, 72.0); // Kích thước font theo kích thước ảnh
        final padding = fontSize * 0.8;

        final textSpan = TextSpan(
          text: dateStr,
          style: TextStyle(
            color: const Color(0xFFFFD700), // Màu vàng
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            shadows: const [
              Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 4), // Bóng đổ
              Shadow(color: Colors.black87, offset: Offset(-1, -1), blurRadius: 3),
            ],
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(); // Tính toán kích thước text

        final x = image.width - textPainter.width - padding; // Vị trí x (góc phải)
        final y = image.height - textPainter.height - padding; // Vị trí y (góc dưới)

        // Vẽ nền đằng sau timestamp
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
          Paint()..color = Colors.black.withAlpha(120), // Nền đen trong suốt
        );

        textPainter.paint(canvas, Offset(x, y)); // Vẽ text timestamp
      }

      final picture = recorder.endRecording(); // Kết thúc vẽ
      final outputImage = await picture.toImage(image.width, image.height); // Tạo image từ picture
      final byteData = await outputImage.toByteData(format: ui.ImageByteFormat.png); // Chuyển thành bytes

      if (byteData != null) {
        await File(destPath).writeAsBytes(byteData.buffer.asUint8List()); // Ghi file
      } else {
        await File(sourcePath).copy(destPath); // Fallback: copy
      }
    } catch (e) {
      debugPrint('Photo processing error: $e, fallback to copy');
      await File(sourcePath).copy(destPath); // Fallback khi lỗi
    }
  }

  // ── Chụp ảnh đơn ──────────────────────────────────────────────────────────────
  /// Chụp một ảnh đơn, áp dụng hiệu ứng và lưu
  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _isTakingPhoto = true);
    try {
      final xFile = await _controller!.takePicture(); // Chụp ảnh từ camera
      final dir = await _getSaveDir(false); // Lấy thư mục lưu ảnh
      final filePath = path.join(dir, 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg'); // Tạo tên file

      await _processCapturedPhoto(xFile.path, filePath); // Xử lý ảnh (filter, HDR, timestamp, mirror)

      setState(() { _isTakingPhoto = false; _lastSavedPath = filePath; _lastSavedIsVideo = false; });
      if (mounted) {
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        final hdrText = _hdrMode != HdrMode.off ? ' (HDR)' : '';
        _showSnackbar('✅ Đã lưu ảnh$hdrText vào $locText', Colors.green);
        _openPreview(filePath, false); // Mở màn hình xem ảnh
      }
    } catch (e) {
      setState(() => _isTakingPhoto = false);
      debugPrint('Take photo error: $e');
      if (mounted) {
        _showSnackbar('❌ Lỗi khi lưu ảnh: $e', Colors.red);
      }
    }
  }

  // ── Chụp liên tiếp (Burst mode) ────────────────────────────────────────────────────────────
  /// Chụp nhiều ảnh liên tiếp với khoảng cách 300ms giữa các frame
  Future<void> _takeBurstPhotos(int count) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isBursting = true;
      _burstProgress = 0;
      _burstTotal = count;
    });
    final dir = await _getSaveDir(false); // Lấy thư mục lưu
    String? lastPath;
    int saved = 0;
    for (int i = 0; i < count; i++) {
      if (!mounted || _controller == null) break;
      try {
        setState(() { _isTakingPhoto = true; _burstProgress = i + 1; }); // Cập nhật tiến trình
        final xFile = await _controller!.takePicture(); // Chụp frame
        final filePath = path.join(dir, 'BURST_${DateTime.now().millisecondsSinceEpoch}_${i + 1}.jpg'); // Tên file

        await _processCapturedPhoto(xFile.path, filePath); // Xử lý ảnh

        lastPath = filePath;
        saved++;
        setState(() => _isTakingPhoto = false);
        // Khoảng cách giữa các frame (~300ms)
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

  // ── Quay video ───────────────────────────────────────────────────────────
  /// Xử lý nút quay video: bắt đầu hoặc dừng
  Future<void> _handleVideoButton() async {
    _isRecording ? await _stopRecording() : await _startRecording();
  }

  /// Bắt đầu quay video
  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.startVideoRecording(); // Bắt đầu ghi
      WakelockPlus.enable(); // Giữ màn hình không tắt
      setState(() { _isRecording = true; _recordingElapsed = 0; });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingElapsed++); // Đếm thời gian quay
      });
      final limit = _videoDurationSeconds(_selectedVideoDuration);
      if (limit > 0) {
        _autoStopTimer = Timer(Duration(seconds: limit), () {
          if (_isRecording) _stopRecording(); // Tự động dừng sau thời gian limit
        });
      }
    } on CameraException catch (e) {
      debugPrint('Start recording error: $e');
    }
  }

  /// Dừng quay video và lưu file
  Future<void> _stopRecording() async {
    if (_controller == null || !_isRecording) return;
    _recordingTimer?.cancel();
    _autoStopTimer?.cancel();

    // Đánh dấu không đang quay ngay để UI cập nhật và tránh dừng 2 lần
    setState(() { _isRecording = false; _recordingElapsed = 0; });

    XFile? xFile;
    try {
      xFile = await _controller!.stopVideoRecording(); // Dừng ghi
    } catch (e) {
      WakelockPlus.disable();
      debugPrint('stopVideoRecording error: $e');
      if (mounted) _showSnackbar('❌ Lỗi dừng ghi video: $e', Colors.red);
      return;
    }

    WakelockPlus.disable();

    // Hiển thị tiến trình lưu (quan trọng cho file lớn trên SD card)
    if (mounted) {
      _showSnackbar('💾 Đang lưu video, vui lòng chờ...', Colors.blueGrey);
    }

    try {
      final srcPath = xFile.path;
      final srcFile = File(srcPath);

      // Kiểm tra file nguồn tồn tại và có nội dung
      if (!srcFile.existsSync() || srcFile.lengthSync() == 0) {
        throw Exception('File video tạm rỗng hoặc không tồn tại: $srcPath');
      }

      final srcSize = srcFile.lengthSync();
      debugPrint('Video source: $srcPath (${(srcSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Xác định thư mục đích
      final dir = await _getSaveDir(true);
      final fileName = 'VID_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final destPath = path.join(dir, fileName);

      // ── Streaming copy: chunk-by-chunk để tránh OOM với file lớn ──
      // Quan trọng cho SD card: File.copy() có thể crash với file > 100MB
      // vì Android giới hạn kích thước copy cross-filesystem.
      await _streamCopyFile(srcPath, destPath);

      // Kiểm tra file đích được ghi đúng (ít nhất 95% kích thước nguồn)
      final destFile = File(destPath);
      final destSize = destFile.existsSync() ? destFile.lengthSync() : 0;
      if (destSize < (srcSize * 0.95).toInt()) {
        throw Exception(
          'File đích không đủ dung lượng: ${(destSize / 1024 / 1024).toStringAsFixed(1)} MB '
          '/ ${(srcSize / 1024 / 1024).toStringAsFixed(1)} MB',
        );
      }

      debugPrint('Video saved: $destPath (${(destSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Xóa file tạm nguồn để giải phóng storage camera
      try { srcFile.deleteSync(); } catch (_) {}

      if (mounted) {
        setState(() { _lastSavedPath = destPath; _lastSavedIsVideo = true; });
        final locText = _storageLocation == StorageLocation.sdcard ? 'thẻ nhớ SD' : 'điện thoại';
        _showSnackbar('✅ Đã lưu video vào $locText', Colors.green);
        _openPreview(destPath, true); // Mở màn hình xem video
      }
    } catch (e) {
      debugPrint('Save video error: $e');
      if (mounted) {
        // Thử fallback: lưu vào bộ nhớ trong điện thoại
        await _saveVideoFallbackToPhone(xFile.path, e.toString());
      }
    }
  }

  /// Copy file chunk-by-chunk để tránh OOM với file video lớn (hundreds of MB)
  /// và không block main thread
  Future<void> _streamCopyFile(String srcPath, String destPath) async {
    final src = File(srcPath);
    final dest = File(destPath);

    // Đảm bảo thư mục cha tồn tại
    final parent = dest.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }

    final input = src.openRead();
    final output = dest.openWrite();
    try {
      // pipe() streams chunk-by-chunk và tự động gọi close() khi xong
      // đảm bảo dữ liệu được flush và commit — KHÔNG gọi flush() hoặc close()
      // lại sau pipe() hoặc sẽ throw StateError.
      await input.pipe(output);
    } catch (e) {
      // Xóa file đích partial khi lỗi
      try {
        if (dest.existsSync()) dest.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Fallback: nếu lưu SD card thất bại, thử lưu vào bộ nhớ trong điện thoại
  Future<void> _saveVideoFallbackToPhone(String srcPath, String originalError) async {
    debugPrint('Attempting phone storage fallback after: $originalError');
    try {
      final srcFile = File(srcPath);
      if (!srcFile.existsSync()) {
        _showSnackbar('❌ Lỗi lưu video: file tạm không còn tồn tại', Colors.red);
        return;
      }

      // Tạm thời ép buộc lưu vào bộ nhớ trong
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

  /// Mở màn hình xem ảnh/video
  void _openPreview(String filePath, bool isVideo) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PreviewScreen(filePath: filePath, isVideo: isVideo),
    ));
  }

  /// Hiển thị thông báo SnackBar
  void _showSnackbar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Đổi chất lượng camera ─────────────────────────────────────────────────────────────
  Future<void> _changeQuality(ResolutionPreset preset) async {
    if (_isRecording) return; // Không đổi khi đang quay
    setState(() { _resolution = preset; _isInitializing = true; });
    await _initCamera(); // Khởi tạo lại camera với chất lượng mới
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // BUILD UI
  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Preview camera (background layer)
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: 60), // Spacer cho topBar
                  Expanded(child: _buildPreviewArea()),
                  _buildBottomControls(),
                ],
              ),
            ),
            // TopBar (foreground layer - luôn ở trên cùng)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Thanh điều khiển trên cùng ───────────────────────────────────────────────────────────
  /// Hiển thị: Flash, HDR, Filter, Chống rung, Timer quay, và các nút Grid/Settings
  Widget _buildTopBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Trái: Flash, HDR, Filter, Chống rung, và Tiêu đề (Có thể scroll) ──
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nút Flash
                  IconButton(
                    icon: Icon(
                      _flashIcon,
                      color: _flashMode != FlashMode.off ? const Color(0xFFFFD700) : Colors.white,
                    ),
                    onPressed: _toggleFlash,
                    tooltip: _mode == CameraMode.photo ? 'Đèn Flash' : 'Đèn chiếu sáng (Torch)',
                  ),
                  // Nút HDR (chỉ chế độ ảnh)
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
                  // Timer quay hoặc Tiêu đề chế độ
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

          // ── Phải: Nút Lưới & Cài đặt (LUÔN HIỂN THỊ, KHÔNG BỊ ẨN) ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút Toggle Lưới 9 ô
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

              // Nút Cài đặt Camera
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
                            ?  [
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

  // ── Preview camera (đúng tỷ lệ, pinch-zoom, chống rung & filter real-time) ──
  /// Xây dựng widget preview camera với các hiệu ứng: chống rung, filter, lật ảnh, và gesture zoom
  Widget _buildCameraPreview() {
    final previewSize = _controller!.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(_controller!);
    }

    final double sensorW = previewSize.height; // Chiều rộng landscape → trục chiều cao portrait
    final double sensorH = previewSize.width;  // Chiều cao landscape → trục chiều rộng portrait

    // Thử thay thế OverflowBox bằng cách đơn giản hơn để tránh tràn lên topBar
    Widget preview = SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: FittedBox(
        fit: BoxFit.cover, // Chứa trong khung để không tràn lên topBar
        child: SizedBox(
          width: sensorW,
          height: sensorH,
          child: CameraPreview(_controller!),
        ),
      ),
    );

    // Áp dụng buffer scale để giảm rung khi Super Steady bật
    if (_stabilizationMode == StabilizationMode.superSteady) {
      preview = Transform.scale(
        scale: 1.04, // Scale nhẹ để có room cho crop
        child: preview,
      );
    }

    // Áp dụng filter màu/beauty real-time 60 FPS GPU
    final matrix = FilterHelper.getMatrix(_selectedFilter);
    if (matrix != null) {
      preview = ColorFiltered(
        colorFilter: ColorFilter.matrix(matrix),
        child: preview,
      );
    }

    // Áp dụng lật ngang cho preview selfie camera trước
    if (_isFrontCamera && _mirrorFrontCamera) {
      preview = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0), // Lật ngang
        child: preview,
      );
    }

    // Gesture Pinch to Zoom
    return GestureDetector(
      onScaleStart: (details) {
        _baseScale = _currentZoom; // Lưu scale cơ bản khi bắt đầu pinch
      },
      onScaleUpdate: (details) {
        final newZoom = (_baseScale * details.scale).clamp(_minAvailableZoom, _maxAvailableZoom);
        _setZoom(newZoom); // Cập nhật zoom
      },
      child: preview,
    );
  }

  // ── Khu vực preview ──────────────────────────────────────────────────────────────
  /// Xây dựng khu vực preview với các overlay: lưới, flash, countdown, badges, settings
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
    return Stack(
      clipBehavior: Clip.none, // Không clip để tránh cắt các overlay
      children: [
        // ── Preview camera: lấp đầy màn hình, giữ tỷ lệ sensor (không méo) ──
        Positioned.fill(
          child: _buildCameraPreview(),
        ),

      // Lưới 9 ô (rule of thirds)
      if (_showGrid) _buildGridOverlay(),

      // Flash nháy khi chụp
      if (_isTakingPhoto)
        Positioned.fill(child: Container(color: Colors.white.withAlpha(200))),

      // Overlay đếm ngược
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

      // Overlay tiến trình chụp liên tiếp
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

      // Badge burst (góc trái trên) khi burst mode bật nhưng không đang chụp
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

      // Badges: Chống rung + Filter + Chất lượng + HDR (góc phải trên)
      Positioned(
        top: 10, right: 10,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Badge chống rung
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
            // Badge filter
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
            // Badge HDR (chỉ chế độ ảnh)
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
            // Badge chất lượng
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

      // ── Thanh chọn Filter nhanh (trên thanh điều khiển dưới) ──
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

      // Panel cài đặt
      if (_showSettings) _buildSettingsPanel(),
    ]);
  }

  // ── Panel cài đặt ────────────────────────────────────────────────────────────
  /// Hiển thị panel cài đặt ở dưới cùng với các tùy chọn: chống rung, filter, lưới, lật ảnh, chất lượng, HDR, timer, burst, timestamp, storage
  Widget _buildSettingsPanel() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65, // Tối đa 65% chiều cao màn hình
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
              // Header với tiêu đề và nút đóng
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

              // Chất lượng
              QualitySelector(selected: _resolution, onChanged: _changeQuality),
              const SizedBox(height: 18),
              // Các tùy chọn theo chế độ
              if (_mode == CameraMode.photo) ...[
                // HDR (chỉ ảnh)
                HdrSelector(
                  selected: _hdrMode,
                  onChanged: (v) => setState(() => _hdrMode = v),
                ),
                const SizedBox(height: 18),
                // Timer chụp ảnh
                TimerSelector(
                  label: 'HẸN GIỜ CHỤP ẢNH',
                  icon: Icons.timer_outlined,
                  options: _photoTimerOptions,
                  selected: _selectedPhotoTimer,
                  onChanged: (v) => setState(() => _selectedPhotoTimer = v),
                ),
                const SizedBox(height: 18),
                // Chụp liên tiếp
                _buildBurstSelector(),
                const SizedBox(height: 18),
                // Timestamp
                TimestampSelector(
                  enabled: _showTimestamp,
                  onChanged: (v) => setState(() => _showTimestamp = v),
                ),
              ] else ...[
                // Timer quay video
                TimerSelector(
                  label: 'THỜI LƯỢNG QUAY TỰ ĐỘNG',
                  icon: Icons.videocam_outlined,
                  options: _videoDurationOptions,
                  selected: _selectedVideoDuration,
                  onChanged: (v) { if (!_isRecording) setState(() => _selectedVideoDuration = v); },
                ),
              ],
              const SizedBox(height: 18),
              // Vị trí lưu (SD card / điện thoại)
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

  // ── Thanh điều khiển dưới cùng ────────────────────────────────────────────────────────────
  /// Hiển thị: Zoom selector, Chế độ (ảnh/video), Thumbnail, Nút chụp/quay, Nút chuyển camera
  Widget _buildBottomControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(top: 8, bottom: 26),
      child: Column(children: [
        // ── Zoom Selector (0.5x, 1x, 2x, 4x, 10x - Mặc định 1x) ──
        ZoomSelector(
          currentZoom: _currentZoom,
          minZoom: _minAvailableZoom,
          maxZoom: _maxAvailableZoom,
          onZoomChanged: _setZoom,
        ),
        const SizedBox(height: 10),
        // Chế độ ảnh/video (ẩn khi đang quay)
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

            // Nút chuyển camera (trước/sau)
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

  /// Selector chế độ ảnh/video
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

  // ── Selector chụp liên tiếp (inline widget) ────────────────────────────────────────────────
  /// Chọn số tấm chụp liên tiếp: Tắt, 3, 5, 7, 9, 15 tấm
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

  /// Nút chụp/quay chính
  Widget _buildShutterButton() {
    if (_mode == CameraMode.photo) {
      // Nút chụp ảnh
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
      // Nút quay video
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

  // ── Overlay lưới 9 ô ────────────────────────────────────────────────────────────
  /// Lưới 3×3 rule-of-thirds với điểm giao highlight
  Widget _buildGridOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(),
        ),
      ),
    );
  }

  // ── Selector lưới trong cài đặt ──────────────────────────────────────────────────
  /// Chọn bật/tắt lưới 9 ô
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

  // ── Selector lật ảnh selfie trong cài đặt ────────────────────────────────────
  /// Chọn bật/tắt lật ảnh cho camera trước
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
            // Badge "Camera trước" khi đang dùng camera trước
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

// ── Painter vẽ lưới 9 ô ────────────────────────────────────────────────────────────────
/// CustomPainter để vẽ lưới 3×3 rule-of-thirds với 4 điểm giao highlight vàng
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(70) // Màu trắng trong suốt
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFFFFD700).withAlpha(180) // Màu vàng trong suốt
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Vẽ 2 đường dọc tại 1/3 và 2/3
    for (int i = 1; i <= 2; i++) {
      final x = w * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, h), linePaint);
    }

    // Vẽ 2 đường ngang tại 1/3 và 2/3
    for (int i = 1; i <= 2; i++) {
      final y = h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
    }

    // Vẽ 4 điểm giao (power points) màu vàng
    for (int col = 1; col <= 2; col++) {
      for (int row = 1; row <= 2; row++) {
        canvas.drawCircle(
          Offset(w * col / 3, h * row / 3),
          3.5, // Bán kính điểm
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false; // Không cần repaint lại
}

// ── Nút chọn chế độ (Ảnh/Video) ────────────────────────────────────────────────────────────────
/// Widget nút để chọn giữa chế độ chụp ảnh và quay video
class _ModeButton extends StatelessWidget {
  final String label; // Nhãn nút
  final bool isSelected; // Có được chọn không
  final VoidCallback onTap; // Callback khi click

  const _ModeButton({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.white.withAlpha(25), // Vàng khi chọn
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

// ── Nút option trong cài đặt ─────────────────────────────────────────────────────────
/// Widget nút option cho các tùy chọn trong cài đặt (lưới, lật ảnh, v.v.)
class _GridOption extends StatelessWidget {
  final IconData icon; // Icon nút
  final String label; // Nhãn nút
  final bool isSelected; // Có được chọn không
  final VoidCallback onTap; // Callback khi click

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
          color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E), // Vàng khi chọn
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
