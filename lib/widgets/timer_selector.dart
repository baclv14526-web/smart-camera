import 'package:flutter/material.dart';

class TimerSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  final String label;
  final IconData? icon;

  const TimerSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: const Color(0xFFFFD700)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: options.map((opt) {
              final sel = opt == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFFD700) : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? const Color(0xFFFFD700) : const Color(0xFF48484A),
                        width: 1.2,
                      ),
                      boxShadow: sel
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withAlpha(80),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
