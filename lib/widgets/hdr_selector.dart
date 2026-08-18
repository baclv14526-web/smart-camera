import 'package:flutter/material.dart';

enum HdrMode { off, auto, on }

class HdrSelector extends StatelessWidget {
  final HdrMode selected;
  final ValueChanged<HdrMode> onChanged;

  const HdrSelector({
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
            Icon(Icons.hdr_enhanced_select, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'CHẾ ĐỘ HDR (THIẾU SÁNG)',
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
            _HdrOption(
              icon: Icons.hdr_off,
              label: 'Tắt',
              isSelected: selected == HdrMode.off,
              onTap: () => onChanged(HdrMode.off),
            ),
            const SizedBox(width: 8),
            _HdrOption(
              icon: Icons.hdr_auto,
              label: 'Tự động',
              isSelected: selected == HdrMode.auto,
              onTap: () => onChanged(HdrMode.auto),
            ),
            const SizedBox(width: 8),
            _HdrOption(
              icon: Icons.hdr_on,
              label: 'Bật HDR',
              isSelected: selected == HdrMode.on,
              onTap: () => onChanged(HdrMode.on),
            ),
          ],
        ),
      ],
    );
  }
}

class _HdrOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _HdrOption({
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}