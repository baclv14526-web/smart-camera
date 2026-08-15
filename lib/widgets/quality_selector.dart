import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class QualitySelector extends StatelessWidget {
  final ResolutionPreset selected;
  final ValueChanged<ResolutionPreset> onChanged;

  const QualitySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const Map<ResolutionPreset, String> presetLabels = {
    ResolutionPreset.high: 'HD',
    ResolutionPreset.veryHigh: 'Full HD',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHẤT LƯỢNG',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: presetLabels.entries.map((entry) {
            final isSelected = entry.key == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFD700)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFFD700)
                          : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
