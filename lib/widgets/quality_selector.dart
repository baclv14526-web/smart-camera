import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class QualitySelector extends StatelessWidget {
  final ResolutionPreset selected;
  final ValueChanged<ResolutionPreset> onChanged;

  const QualitySelector({super.key, required this.selected, required this.onChanged});

  static const Map<ResolutionPreset, String> _labels = {
    ResolutionPreset.high: 'HD (720p)',
    ResolutionPreset.veryHigh: 'Full HD (1080p)',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.high_quality, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'CHẤT LƯỢNG',
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
          children: _labels.entries.map((e) {
            final sel = e.key == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFFFD700) : const Color(0xFF48484A),
                      width: 1.2,
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withAlpha(80),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
