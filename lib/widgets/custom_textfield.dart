import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CustomTextField extends StatelessWidget {
  final TextInputType? textInputType;
  final Widget? prefix;
  final String hint;
  final double borderRadius;
  final Color? borderColor;
  final Color? fillColor;
  final double? height;
  final Widget? suffix;
  final bool autofocus;
  final bool obscureText;
  final bool readOnly;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextCapitalization textCapitalization;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final Function(String?)? onSaved;
  final Function(String?)? onChanged;
  final TextInputAction textInputAction;
  final int? maxLength;
  final int? maxLines;
  final AutovalidateMode autovalidateMode;

  const CustomTextField({
    super.key,
    this.textInputType,
    this.prefix,
    this.hint = "",
    this.borderRadius = 8,
    this.borderColor,
    this.fillColor,
    this.height,
    this.suffix,
    this.autofocus = false,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
    this.contentPadding,
    this.textCapitalization = TextCapitalization.none,
    this.controller,
    this.inputFormatters,
    this.validator,
    this.onSaved,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
    this.maxLength,
    this.maxLines = 1,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(
        color: borderColor ?? Colors.transparent,
        width: borderColor == null ? 0 : 1,
      ),
    );

    return SizedBox(
      height: height,
      child: TextFormField(
        onChanged: onChanged,
        cursorWidth: 2,
        autofocus: autofocus,
        onTap: onTap,
        readOnly: readOnly,
        keyboardAppearance: Theme.of(context).brightness,
        textInputAction: textInputAction,
        obscureText: obscureText,
        maxLength: maxLength,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        controller: controller,
        validator: validator,
        autovalidateMode: autovalidateMode,
        keyboardType: textInputType ?? TextInputType.text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12.sp,
              color: Colors.black,
            ),
        textCapitalization: textCapitalization,
        onSaved: onSaved,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fillColor ?? Colors.white.withOpacity(0.2),
          contentPadding: contentPadding ??
              EdgeInsets.symmetric(vertical: 15.h, horizontal: 10.w),
          counterText: "",
          prefixIcon: prefix,
          suffixIcon: suffix,
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.black.withOpacity(0.4),
            fontSize: 12.sp,
            fontWeight: FontWeight.w400,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: border.borderSide.copyWith(
              color: borderColor ?? Theme.of(context).primaryColor,
              width: 1,
            ),
          ),
          errorBorder: border.copyWith(
            borderSide: const BorderSide(color: Colors.red, width: 0.5),
          ),
          focusedErrorBorder: border.copyWith(
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          disabledBorder: border.copyWith(
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
