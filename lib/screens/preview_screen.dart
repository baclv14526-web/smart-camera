import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const PreviewScreen({super.key, required this.filePath, required this.isVideo});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    _videoController = controller;
    await controller.initialize();
    await controller.play();
    setState(() { _initialized = true; _isPlaying = true; });
    controller.addListener(() {
      if (mounted && controller.value.position >= controller.value.duration) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final ctrl = _videoController;
    if (ctrl == null) return;
    setState(() {
      if (ctrl.value.isPlaying) { ctrl.pause(); _isPlaying = false; }
      else { ctrl.play(); _isPlaying = true; }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isVideo ? 'Xem trước video' : 'Xem trước ảnh',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Color(0xFFFFD700)),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Xong',
          ),
        ],
      ),
      body: Center(
        child: widget.isVideo ? _buildVideoPlayer() : _buildImage(),
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildVideoPlayer() {
    final ctrl = _videoController;
    if (ctrl == null || !_initialized) {
      return const CircularProgressIndicator(color: Color(0xFFFFD700));
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: ctrl.value.aspectRatio, child: VideoPlayer(ctrl)),
        if (!_isPlaying)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
          ),
      ]),
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      child: Image.file(File(widget.filePath), fit: BoxFit.contain),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        if (widget.isVideo)
          _BottomBtn(
            icon: _isPlaying ? Icons.pause : Icons.play_arrow,
            label: _isPlaying ? 'Tạm dừng' : 'Phát',
            onTap: _togglePlay,
          ),
        _BottomBtn(
          icon: Icons.folder_open,
          label: 'Đã lưu',
          color: const Color(0xFFFFD700),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File đã lưu vào bộ nhớ thiết bị'),
              backgroundColor: Colors.green,
            ),
          ),
        ),
        _BottomBtn(
          icon: Icons.close,
          label: 'Đóng',
          onTap: () => Navigator.pop(context),
        ),
      ]),
    );
  }
}

class _BottomBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _BottomBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }
}
