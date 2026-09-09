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
          icon: Icons.info_outline,
          label: 'Chi tiết file',
          color: const Color(0xFFFFD700),
          onTap: () => _showFileInfoModal(context),
        ),
        _BottomBtn(
          icon: Icons.close,
          label: 'Đóng',
          onTap: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  void _showFileInfoModal(BuildContext context) {
    final file = File(widget.filePath);
    final exists = file.existsSync();
    final sizeStr = exists
        ? '${(file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB'
        : 'Không xác định';
    final modifiedStr = exists
        ? file.lastModifiedSync().toString().split('.').first
        : 'N/A';

    final isSdCard = widget.filePath.contains('/storage/') &&
        !widget.filePath.contains('/storage/emulated/0');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSdCard ? Icons.sd_card : Icons.phone_android,
                  color: const Color(0xFFFFD700),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isSdCard ? 'Lưu tại Thẻ nhớ microSD' : 'Lưu tại Bộ nhớ máy',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            _infoRow('Loại tệp:', widget.isVideo ? 'Video (MP4)' : 'Ảnh chụp (JPEG)'),
            const SizedBox(height: 10),
            _infoRow('Kích thước:', sizeStr),
            const SizedBox(height: 10),
            _infoRow('Thời gian:', modifiedStr),
            const SizedBox(height: 10),
            _infoRow('Đường dẫn đầy đủ:', widget.filePath, isPath: true),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String title, String val, {bool isPath = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 2),
        SelectableText(
          val,
          style: TextStyle(
            color: isPath ? const Color(0xFFFFD700) : Colors.white,
            fontSize: isPath ? 12 : 14,
            fontWeight: isPath ? FontWeight.normal : FontWeight.w500,
          ),
        ),
      ],
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
