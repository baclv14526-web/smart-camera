import 'package:flutter/material.dart';

class ZoomSelector extends StatelessWidget {
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final double minZoom;
  final double maxZoom;

  static const List<double> zoomPresets = [0.5, 1.0, 2.0, 4.0, 10.0];

  const ZoomSelector({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    this.minZoom = 1.0,
    this.maxZoom = 10.0,
  });

  String _formatLabel(double zoom) {
    if (zoom == 0.5) return '0.5';
    if (zoom == 1.0) return '1x';
    if (zoom == 2.0) return '2x';
    if (zoom == 4.0) return '4x';
    if (zoom == 10.0) return '10x';
    return '${zoom.toStringAsFixed(1)}x';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: zoomPresets.map((preset) {
          final isSelected = (currentZoom - preset).abs() < 0.15;
          final isAvailable = preset <= maxZoom && preset >= minZoom;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: isAvailable ? () => onZoomChanged(preset) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isSelected ? 38 : 32,
                height: isSelected ? 38 : 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFD700)
                      : isAvailable
                          ? const Color(0xFF222224)
                          : const Color(0xFF18181A),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFFD700)
                        : isAvailable
                            ? const Color(0xFF38383A)
                            : Colors.white10,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withAlpha(100),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    _formatLabel(preset),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : isAvailable
                              ? Colors.white
                              : Colors.white24,
                      fontSize: isSelected ? 12 : 11,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
