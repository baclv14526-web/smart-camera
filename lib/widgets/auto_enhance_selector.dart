import 'package:flutter/material.dart';

/// Widget cài đặt Tự động tối ưu màu sắc & ánh sáng (AI Auto Enhance)
class AutoEnhanceSelector extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const AutoEnhanceSelector({
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
            Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'TỰ ĐỘNG CÂN BẰNG MÀU & ÁNH SÁNG',
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
            _OptionButton(
              icon: Icons.auto_fix_high,
              label: 'Tự động tối ưu',
              isSelected: enabled,
              onTap: () => onChanged(true),
            ),
            const SizedBox(width: 10),
            _OptionButton(
              icon: Icons.do_not_disturb_on_outlined,
              label: 'Gốc (Tắt)',
              isSelected: !enabled,
              onTap: () => onChanged(false),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          enabled
              ? '✨ Tự động cân bằng trắng, tối ưu độ tương phản, ánh sáng và màu sắc rực rỡ tự nhiên cho cả camera trước & sau.'
              : 'Chụp ảnh theo độ phơi sáng và màu sắc mặc định của cảm biến.',
          style: TextStyle(
            color: Colors.white.withAlpha(140),
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionButton({
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
