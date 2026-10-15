import 'package:flutter/material.dart';

class NameAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final TextStyle? textStyle;

  const NameAvatar({
    super.key,
    required this.name,
    this.radius = 12,
    this.textStyle,
  });

  // Extract up to two initials from the name
  String _getInitials(String fullName) {
    if (fullName.trim().isEmpty) return '?';

    List<String> nameParts = fullName.trim().split(RegExp(r'\s+'));
    String initials = nameParts.first[0];

    if (nameParts.length > 1) {
      initials += nameParts.last[0];
    }

    return initials.toUpperCase();
  }

  // Generate a deterministic color based on the name's hash code
  Color _getColorFromName(String fullName) {
    if (fullName.trim().isEmpty) return Colors.grey;

    // Use standard String hashCode
    final int hash = fullName.hashCode;

    // Material primary colors palette to choose from
    final List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.amber,
    ];

    // Select a color safely using the modulo operator
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final String initials = _getInitials(name);
    final Color backgroundColor = _getColorFromName(name);

    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: backgroundColor, width: .5),
      ),
      child: Text(
        initials,
        style:
            textStyle ??
            TextStyle(
              color: backgroundColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
      ),
    );
  }
}
