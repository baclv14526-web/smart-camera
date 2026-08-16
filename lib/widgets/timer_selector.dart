import 'package:flutter/material.dart';

class TimerSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;
  final String label;

  const TimerSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: Colors.white70, fontSize: 12,
              fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((opt) {
              final sel = opt == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFFD700) : Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? const Color(0xFFFFD700) : Colors.white24),
                    ),
                    child: Text(opt,
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      )),
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
