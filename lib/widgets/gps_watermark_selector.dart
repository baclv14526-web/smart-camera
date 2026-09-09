import 'package:flutter/material.dart';

class GpsWatermarkSelector extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const GpsWatermarkSelector({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.location_on_outlined, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'TỌA ĐỘ GPS TRÊN ẢNH',
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
          children: [
            _GpsOption(
              icon: Icons.place,
              label: 'Hiện vị trí GPS',
              isSelected: enabled,
              onTap: () => onChanged(true),
            ),
            const SizedBox(width: 10),
            _GpsOption(
              icon: Icons.location_off_outlined,
              label: 'Ẩn',
              isSelected: !enabled,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }
}

class _GpsOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GpsOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFFD700).withAlpha(40)
                : Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFFFFD700) : Colors.white24,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? const Color(0xFFFFD700) : Colors.white60,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
