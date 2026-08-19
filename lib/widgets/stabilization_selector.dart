import 'package:flutter/material.dart';

enum StabilizationMode {
  off,
  standard,
  superSteady,
}

class StabilizationOption {
  final StabilizationMode mode;
  final String label;
  final String description;
  final IconData icon;

  const StabilizationOption({
    required this.mode,
    required this.label,
    required this.description,
    required this.icon,
  });
}

class StabilizationSelector extends StatelessWidget {
  final StabilizationMode selected;
  final ValueChanged<StabilizationMode> onChanged;

  static const List<StabilizationOption> options = [
    StabilizationOption(
      mode: StabilizationMode.off,
      label: 'Tắt',
      description: 'Chụp trên tripod / chân máy',
      icon: Icons.motion_photos_off,
    ),
    StabilizationOption(
      mode: StabilizationMode.standard,
      label: 'Chuẩn OIS',
      description: 'Chống rung quang học cầm tay',
      icon: Icons.motion_photos_on,
    ),
    StabilizationOption(
      mode: StabilizationMode.superSteady,
      label: 'Siêu Chống Rung',
      description: 'Khử rung chuyển động thể thao/chạy bộ',
      icon: Icons.motion_photos_auto,
    ),
  ];

  const StabilizationSelector({
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
            Icon(Icons.motion_photos_on, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'CHỐNG RUNG HÌNH ẢNH (OIS / EIS)',
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
        Row(
          children: options.map((opt) {
            final isSelected = opt.mode == selected;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => onChanged(opt.mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(14),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          opt.icon,
                          size: 20,
                          color: isSelected ? Colors.black87 : Colors.white70,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          opt.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.black87 : Colors.white,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ],
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
