// lib/widgets/app_button.dart
import 'package:flutter/material.dart';
import '../app_theme.dart'; // This points to your app_theme.dart file

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool isPrimary; // true = main rose-gold button, false = softer button

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isPrimary = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double
          .infinity, // makes button full width (like your Procedure screen)
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 22) : const SizedBox.shrink(),
        label: Text(label),
        style: isPrimary
            ? MyApp.primaryRoseButton
            : MyApp.secondaryOutlineButton(),
      ),
    );
  }
}
