import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PreviewScreen extends StatefulWidget {
  final String filePath;
  final bool isVideo;

  const PreviewScreen({
    super.key,
    required this.filePath,
    required this.isVideo,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  VideoPlayerController? _videoController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoController =
          VideoPlayerController.file(File(widget.filePath))
            ..initialize().then((_) {
              setState(() {});
              _videoController!.play();
              _isPlaying = true;
            });
      _videoController!.addListener(() {
        if (_videoController!.value.position ==
            _videoController!.value.duration) {
          setState(() => _isPlaying = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
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
            tooltip: 'Đã lưu',
          ),
        ],
      ),
      body: Center(
        child: widget.isVideo ? _buildVideoPlayer() : _buildImagePreview(),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null ||
        !_videoController!.value.isInitialized) {
      return const CircularProgressIndicator(color: Color(0xFFFFD700));
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
          if (!_isPlaying)
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(16),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 48,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return InteractiveViewer(
      child: Image.file(File(widget.filePath), fit: BoxFit.contain),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (widget.isVideo) ...[
            _BottomButton(
              icon: _isPlaying ? Icons.pause : Icons.play_arrow,
              label: _isPlaying ? 'Tạm dừng' : 'Phát',
              onTap: _togglePlay,
            ),
          ],
          _BottomButton(
            icon: Icons.save_alt,
            label: 'Đã lưu',
            color: const Color(0xFFFFD700),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('File đã được lưu vào thư mục Pictures'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
          _BottomButton(
            icon: Icons.close,
            label: 'Đóng',
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _togglePlay() {
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isPlaying = false;
      } else {
        _videoController!.play();
        _isPlaying = true;
      }
    });
  }
}

class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _BottomButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
