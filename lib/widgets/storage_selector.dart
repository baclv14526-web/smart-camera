import 'package:flutter/material.dart';

enum StorageLocation { phone, sdcard }

class StorageSelector extends StatelessWidget {
  final StorageLocation selected;
  final ValueChanged<StorageLocation> onChanged;
  final bool sdcardAvailable;

  const StorageSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.sdcardAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LƯU VÀO',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StorageOption(
              icon: Icons.phone_android,
              label: 'Điện thoại',
              isSelected: selected == StorageLocation.phone,
              isEnabled: true,
              onTap: () => onChanged(StorageLocation.phone),
            ),
            const SizedBox(width: 8),
            _StorageOption(
              icon: Icons.sd_card,
              label: 'Thẻ nhớ (SD)',
              isSelected: selected == StorageLocation.sdcard,
              isEnabled: sdcardAvailable,
              onTap: sdcardAvailable ? () => onChanged(StorageLocation.sdcard) : null,
            ),
          ],
        ),
        if (!sdcardAvailable)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '⚠️ Không tìm thấy thẻ nhớ ngoài',
              style: TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _StorageOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback? onTap;

  const _StorageOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? const Color(0xFFFFD700)
        : isEnabled
            ? Colors.white.withAlpha(25)
            : Colors.white.withAlpha(10);
    final borderColor = isSelected
        ? const Color(0xFFFFD700)
        : isEnabled
            ? Colors.white24
            : Colors.white12;
    final textColor = isSelected
        ? Colors.black
        : isEnabled
            ? Colors.white
            : Colors.white30;
    final iconColor = isSelected
        ? Colors.black87
        : isEnabled
            ? Colors.white70
            : Colors.white24;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
