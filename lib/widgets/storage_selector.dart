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
        const Row(
          children: [
            Icon(Icons.save_outlined, size: 16, color: Color(0xFFFFD700)),
            SizedBox(width: 6),
            Text(
              'VỊ TRÍ LƯU TRỮ',
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
            _StorageOption(
              icon: Icons.phone_android,
              label: 'Điện thoại',
              isSelected: selected == StorageLocation.phone,
              isEnabled: true,
              onTap: () => onChanged(StorageLocation.phone),
            ),
            const SizedBox(width: 10),
            _StorageOption(
              icon: Icons.sd_card,
              label: 'Thẻ nhớ microSD',
              isSelected: selected == StorageLocation.sdcard,
              isEnabled: sdcardAvailable,
              onTap: sdcardAvailable ? () => onChanged(StorageLocation.sdcard) : null,
            ),
          ],
        ),
        if (!sdcardAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withAlpha(80)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Text(
                    'Không phát hiện thẻ nhớ microSD ngoài',
                    style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
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
            ? const Color(0xFF2C2C2E)
            : const Color(0xFF1E1E20);
    final borderColor = isSelected
        ? const Color(0xFFFFD700)
        : isEnabled
            ? const Color(0xFF48484A)
            : const Color(0xFF333336);
    final textColor = isSelected
        ? Colors.black
        : isEnabled
            ? Colors.white
            : Colors.white38;
    final iconColor = isSelected
        ? Colors.black87
        : isEnabled
            ? Colors.white70
            : Colors.white24;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
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
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
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

