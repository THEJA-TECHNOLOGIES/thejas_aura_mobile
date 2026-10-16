import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:theja_aura/core/theme/app_theme.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    required this.hintText,
    this.keyboardType,
    this.focusNode,
    this.obscureText = false,
    this.autofillHints,
    this.validator,
    this.controller,
    this.formatter,
    this.onFieldSubmitted,
    this.onSuffixTap,
    required this.showSuffixIcon,
    this.suffix,
    this.borderColor = const Color(0xFFE7E7E7),
    this.minLines = 1,
    this.maxLines = 1,
    this.expands = false,
    this.textAlignVertical,
    this.contentPadding,
    this.onChanged,
    this.maxLength,
    this.isRequired = false,
    this.readOnly = false,
    this.enabled = true,
    this.prefixIcon,
    this.initialValue,
    this.errorText,
    this.textInputAction,
    this.autovalidateMode,
    this.useUnderLineBorder = false,
  });

  final bool useUnderLineBorder;
  final String? label;
  final String hintText;
  final String? errorText;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final Function(String)? validator;
  final TextEditingController? controller;
  final List<TextInputFormatter>? formatter;
  final Function(String)? onFieldSubmitted;
  final Function()? onSuffixTap;
  final bool showSuffixIcon;
  final Widget? suffix;
  final Color borderColor;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool expands;
  final bool isRequired;
  final TextAlignVertical? textAlignVertical;
  final EdgeInsetsGeometry? contentPadding;
  final Function(String)? onChanged;
  final bool readOnly;
  final bool enabled;
  final Widget? prefixIcon;
  final String? initialValue;
  final TextInputAction? textInputAction;
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.appTypography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (label != null)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: label,
                  style: typography.bodyLarge.copyWith(
                    color: colors.text5,
                    fontWeight: FontWeight.w500,
                    height: 1.8,
                  ),
                ),
                if (isRequired)
                  TextSpan(
                    text: ' *',
                    style: typography.titleMedium.copyWith(
                      color: colors.secondary,
                    ),
                  ),
              ],
            ),
          ),
        TextFormField(
          cursorColor: colors.primary,
          readOnly: readOnly,
          autovalidateMode: autovalidateMode,
          enabled: enabled,
          initialValue: initialValue,
          decoration: InputDecoration(
            filled: true,
            fillColor: colors.surfaceRaised,
            suffixIcon: showSuffixIcon ? suffix : null,
            prefixIcon: prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: prefixIcon,
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            contentPadding:
                contentPadding ??
                EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            border: useUnderLineBorder
                ? UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                  )
                : OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
            enabledBorder: useUnderLineBorder
                ? UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                  )
                : OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
            disabledBorder: useUnderLineBorder
                ? UnderlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                  )
                : OutlineInputBorder(
                    borderSide: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
            focusedBorder: useUnderLineBorder
                ? UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.primary),
                  )
                : OutlineInputBorder(
                    borderSide: BorderSide(color: colors.primary),
                    borderRadius: BorderRadius.circular(12),
                  ),
            errorBorder: useUnderLineBorder
                ? UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.error),
                  )
                : OutlineInputBorder(
                    borderSide: BorderSide(color: colors.error),
                    borderRadius: BorderRadius.circular(12),
                  ),
            floatingLabelBehavior: maxLines > 1
                ? FloatingLabelBehavior.always
                : FloatingLabelBehavior.auto,
            alignLabelWithHint: maxLines > 1,
            hintText: hintText,
            errorText: errorText,
            hintStyle: typography.bodyMedium.copyWith(
              color: colors.textTertiary,
            ),
            errorStyle: typography.bodySmall.copyWith(color: colors.error),
          ),
          style: typography.bodyMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          keyboardType: keyboardType,
          focusNode: focusNode,
          obscureText: obscureText,
          // obscuringCharacter: "*",
          onChanged: onChanged,
          autofillHints: autofillHints,
          inputFormatters: formatter,
          controller: controller,
          minLines: expands ? null : minLines,
          maxLines: expands ? null : maxLines,
          maxLength: maxLength,
          expands: expands,
          textAlignVertical: textAlignVertical,
          textInputAction: textInputAction,
          onTapOutside: (event) {
            FocusScope.of(context).requestFocus(FocusNode());
          },
          validator: (value) => validator != null ? validator!(value!) : null,
          onFieldSubmitted: onFieldSubmitted,
          buildCounter: maxLength != null
              ? (
                  BuildContext context, {
                  required int currentLength,
                  required bool isFocused,
                  required int? maxLength,
                }) {
                  return Text(
                    '$currentLength/$maxLength',
                    style: TextStyle(
                      color: const Color(0xFFB0B0B0),
                      fontSize: 12,
                    ),
                  );
                }
              : null,
        ),
      ],
    );
  }
}
