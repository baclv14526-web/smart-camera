import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nguồn âm thanh khi chụp ảnh / bắt đầu quay video.
enum CaptureSoundSource { off, defaultClick, customFile }

/// Phát tiếng "tách, tách" mặc định hoặc file mp3 người dùng chọn trong Cài đặt.
class CaptureSoundService {
  CaptureSoundService._();
  static final CaptureSoundService instance = CaptureSoundService._();

  static const defaultAsset = 'sounds/tach_tach.wav';
  static const _keySource = 'capture_sound_source';
  static const _keyCustomPath = 'capture_sound_custom_path';

  final AudioPlayer _player = AudioPlayer();
  CaptureSoundSource source = CaptureSoundSource.defaultClick;
  String? customPath;
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setPlayerMode(PlayerMode.lowLatency);
    try {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (e) {
      debugPrint('CaptureSound audio context: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySource);
    source = CaptureSoundSource.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => CaptureSoundSource.defaultClick,
    );
    customPath = prefs.getString(_keyCustomPath);
    _ready = true;
  }

  String get customFileName {
    final path = customPath;
    if (path == null || path.isEmpty) return '';
    return p.basename(path);
  }

  Future<void> setSource(CaptureSoundSource next) async {
    source = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySource, next.name);
  }

  Future<void> playCaptureSound() async {
    await init();
    if (source == CaptureSoundSource.off) return;
    try {
      await _player.stop();
      if (source == CaptureSoundSource.customFile &&
          customPath != null &&
          File(customPath!).existsSync()) {
        await _player.play(DeviceFileSource(customPath!));
      } else {
        await _player.play(AssetSource(defaultAsset));
      }
    } catch (e) {
      debugPrint('CaptureSound play error: $e');
    }
  }

  Future<void> preview() async {
    await playCaptureSound();
  }

  /// Chọn file mp3/wav từ máy, copy vào thư mục app để dùng lâu dài.
  Future<bool> pickCustomSound() async {
    await init();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
      withData: false,
    );
    final picked = result?.files.single.path;
    if (picked == null || picked.isEmpty) return false;

    final ext = p.extension(picked).toLowerCase();
    final dir = await getApplicationDocumentsDirectory();
    final dest = File(p.join(dir.path, 'custom_capture_sound$ext'));
    await File(picked).copy(dest.path);

    customPath = dest.path;
    source = CaptureSoundSource.customFile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomPath, dest.path);
    await prefs.setString(_keySource, source.name);
    return true;
  }

  Future<void> dispose() async {
    await _player.dispose();
    _ready = false;
  }
}
