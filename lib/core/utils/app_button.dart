import 'package:material_ui/material_ui.dart';

class AppButton extends StatefulWidget {
  final String text;
  final Color color;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;
  final double? width;
  final double borderRadius;
  final Widget? icon;
  final BoxBorder? side;
  final bool isLoading;
  final FocusNode? focusNode;

  const AppButton({
    super.key,
    required this.text,
    required this.color,
    this.onPressed,
    this.padding,
    this.textStyle,
    this.width,
    this.borderRadius = 24.0,
    this.icon,
    this.side,
    this.isLoading = false,
    this.focusNode,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final shadow = _isFocused
        ? [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.6),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ];

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.side,
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: widget.focusNode,
          onFocusChange: (focused) {
            if (_isFocused != focused) {
              setState(() {
                _isFocused = focused;
              });
            }
          },
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Padding(
            padding:
                widget.padding ??
                const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isLoading)
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else ...[
                  if (widget.icon != null) ...[
                    widget.icon!,
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.text,
                    style:
                        widget.textStyle ??
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
