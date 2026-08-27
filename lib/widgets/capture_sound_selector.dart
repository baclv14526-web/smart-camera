import 'package:flutter/material.dart';

import '../services/capture_sound_service.dart';

/// Cấu hình âm thanh chụp ảnh / bắt đầu quay video trong panel Cài đặt.
class CaptureSoundSelector extends StatelessWidget {
  final CaptureSoundSource selected;
  final String customFileName;
  final ValueChanged<CaptureSoundSource> onChanged;
  final VoidCallback onPickFile;
  final VoidCallback onPreview;

  const CaptureSoundSelector({
    super.key,
    required this.selected,
    required this.customFileName,
    required this.onChanged,
    required this.onPickFile,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.volume_up_outlined, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'ÂM THANH CHỤP / QUAY',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SoundOption(
              icon: Icons.volume_off_outlined,
              label: 'Tắt',
              isSelected: selected == CaptureSoundSource.off,
              onTap: () => onChanged(CaptureSoundSource.off),
            ),
            _SoundOption(
              icon: Icons.camera,
              label: 'Tách tách',
              isSelected: selected == CaptureSoundSource.defaultClick,
              onTap: () => onChanged(CaptureSoundSource.defaultClick),
            ),
            _SoundOption(
              icon: Icons.audio_file_outlined,
              label: 'File mp3',
              isSelected: selected == CaptureSoundSource.customFile,
              onTap: () => onChanged(CaptureSoundSource.customFile),
            ),
          ],
        ),
        if (selected != CaptureSoundSource.off) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (selected == CaptureSoundSource.customFile) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: onPickFile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF48484A), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open, size: 16, color: Color(0xFFFFD700)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              customFileName.isEmpty
                                  ? 'Chọn file abc.mp3...'
                                  : customFileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: customFileName.isEmpty
                                    ? Colors.white54
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: onPreview,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF48484A), width: 1.2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, size: 16, color: Color(0xFFFFD700)),
                      SizedBox(width: 4),
                      Text(
                        'Nghe thử',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SoundOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SoundOption({
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
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
