import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class QualitySelector extends StatelessWidget {
  final ResolutionPreset selected;
  final ValueChanged<ResolutionPreset> onChanged;

  const QualitySelector({super.key, required this.selected, required this.onChanged});

  static const Map<ResolutionPreset, String> _labels = {
    ResolutionPreset.high: 'HD  (720p)',
    ResolutionPreset.veryHigh: 'Full HD  (1080p)',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CHẤT LƯỢNG',
            style: TextStyle(
              color: Colors.white70, fontSize: 12,
              fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Row(
          children: _labels.entries.map((e) {
            final sel = e.key == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFFFFD700) : Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? const Color(0xFFFFD700) : Colors.white24),
                  ),
                  child: Text(e.value,
                    style: TextStyle(
                      color: sel ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    )),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
