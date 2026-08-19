import 'package:flutter/material.dart';

enum CameraFilter {
  none,
  beauty,
  vivid,
  warm,
  vintage,
  cinematic,
  mono,
}

class FilterInfo {
  final CameraFilter type;
  final String label;
  final IconData icon;
  final List<double>? matrix;

  const FilterInfo({
    required this.type,
    required this.label,
    required this.icon,
    this.matrix,
  });
}

class FilterHelper {
  static const List<FilterInfo> filters = [
    FilterInfo(
      type: CameraFilter.none,
      label: 'Gốc',
      icon: Icons.filter_none,
      matrix: null,
    ),
    FilterInfo(
      type: CameraFilter.beauty,
      label: 'Làm Đẹp',
      icon: Icons.face_retouching_natural,
      // Soft skin tone: subtle brightness boost + soft pink warmth + smooth highlights
      matrix: [
        1.08, 0.02, 0.02, 0.0, 12.0,
        0.02, 1.05, 0.02, 0.0, 10.0,
        0.02, 0.02, 1.03, 0.0, 14.0,
        0.0,  0.0,  0.0,  1.0, 0.0,
      ],
    ),
    FilterInfo(
      type: CameraFilter.vivid,
      label: 'Tươi Tắn',
      icon: Icons.wb_sunny_outlined,
      // Boosted saturation and vibrance for rich greens, blues, reds
      matrix: [
        1.25, -0.12, -0.05, 0.0, 0.0,
        -0.08, 1.25, -0.05, 0.0, 0.0,
        -0.08, -0.10, 1.30, 0.0, 0.0,
        0.0,   0.0,   0.0,  1.0, 0.0,
      ],
    ),
    FilterInfo(
      type: CameraFilter.warm,
      label: 'Ấm Áp',
      icon: Icons.wb_twilight,
      // Golden hour warm sun glow: boost red & yellow, soft contrast
      matrix: [
        1.18, 0.05, -0.05, 0.0, 15.0,
        0.03, 1.10, -0.05, 0.0, 10.0,
        -0.10, -0.05, 0.90, 0.0, -8.0,
        0.0,   0.0,   0.0,  1.0, 0.0,
      ],
    ),
    FilterInfo(
      type: CameraFilter.vintage,
      label: 'Cổ Điển',
      icon: Icons.camera_roll_outlined,
      // Retro film aesthetic: faded blacks, sepia/greenish undertone
      matrix: [
        0.95, 0.15, 0.05, 0.0, 18.0,
        0.05, 0.90, 0.10, 0.0, 12.0,
        0.10, 0.05, 0.80, 0.0, 8.0,
        0.0,  0.0,  0.0,  1.0, 0.0,
      ],
    ),
    FilterInfo(
      type: CameraFilter.cinematic,
      label: 'Điện Ảnh',
      icon: Icons.movie_filter_outlined,
      // Teal & Orange cinema grading: warm highlights, rich teal shadows
      matrix: [
        1.20, -0.05, -0.05, 0.0, 5.0,
        -0.05, 1.05, 0.08, 0.0, -5.0,
        -0.12, 0.10, 1.15, 0.0, 12.0,
        0.0,   0.0,   0.0, 1.0, 0.0,
      ],
    ),
    FilterInfo(
      type: CameraFilter.mono,
      label: 'Đen Trắng',
      icon: Icons.monochrome_photos,
      // High-contrast classic black & white
      matrix: [
        0.299, 0.587, 0.114, 0.0, 0.0,
        0.299, 0.587, 0.114, 0.0, 0.0,
        0.299, 0.587, 0.114, 0.0, 0.0,
        0.0,   0.0,   0.0,   1.0, 0.0,
      ],
    ),
  ];

  static List<double>? getMatrix(CameraFilter type) {
    return filters.firstWhere((f) => f.type == type).matrix;
  }

  static String getLabel(CameraFilter type) {
    return filters.firstWhere((f) => f.type == type).label;
  }
}

/// Horizontal scrolling quick filter bar shown on the camera viewfinder
class FilterCarouselBar extends StatelessWidget {
  final CameraFilter selected;
  final ValueChanged<CameraFilter> onSelected;

  const FilterCarouselBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: FilterHelper.filters.length,
        itemBuilder: (context, index) {
          final filter = FilterHelper.filters[index];
          final isSelected = filter.type == selected;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelected(filter.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF3E3E42),
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
                      filter.icon,
                      size: 15,
                      color: isSelected ? Colors.black87 : Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      filter.label,
                      style: TextStyle(
                        color: isSelected ? Colors.black87 : Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Filter selector widget embedded inside Settings Panel
class FilterSettingsSelector extends StatelessWidget {
  final CameraFilter selected;
  final ValueChanged<CameraFilter> onChanged;

  const FilterSettingsSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'BỘ LỌC MÀU & LÀM ĐẸP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FilterHelper.filters.map((filter) {
            final isSelected = filter.type == selected;
            return GestureDetector(
              onTap: () => onChanged(filter.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF444446),
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
                      filter.icon,
                      size: 16,
                      color: isSelected ? Colors.black87 : Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      filter.label,
                      style: TextStyle(
                        color: isSelected ? Colors.black87 : Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
