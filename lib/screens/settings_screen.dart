import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../main.dart' show RestartWidget;
import '../providers/procedure_logs_provider.dart';
import '../services/notification_service.dart';
import '../utils/app_prefs.dart';
import '../utils/procedure_deletion.dart';
import '../widgets/skincare_style_picker.dart';
import '../utils/premium_access.dart';
import '../widgets/clinical_metric_label.dart';
import '../widgets/clinical_section_header.dart';
import '../utils/skin_metric_labels.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final Uri _privacyPolicyUri = Uri.parse(
    'https://example.com/aesthetic-skin-tracker/privacy-policy',
  );
  String _savedName = '';
  String _savedAgeRange = '';
  List<String> _savedSkinConcerns = const [];
  String _savedClinic = '';
  String _savedProcedure = '';
  String? _savedProfilePicture;
  int _savedScanCount = 0;
  DateTime? _lastScanAt;
  bool _isPremiumUser = false;
  bool _testingModeAvailable = false;
  bool _testingPremiumActive = false;
  bool _verboseDiagnosticsEnabled = false;
  bool _notificationsEnabled = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _ageRanges = const [
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55+',
  ];
  final List<String> _skinConcernOptions = const [
    'Rhytids',
    'Pore Visibility',
    'Hyperpigmentation',
    'Acne Scars',
    'Erythema',
    'Dullness',
    'Skin Hydration Level',
    'Sebum / Oiliness',
    'Skin Laxity',
    'Skin Tone Uniformity',
    'Other',
  ];
  final List<String> _procedureTypes = const [
    'BBL',
    'Liposuction',
    'Tummy Tuck',
    'Arm Contouring',
    'Thigh Lift',
    'Halo Laser',
    'Microneedling',
    'RF Microneedling',
    'Fractional Laser',
    'CO2 Laser Resurfacing',
    'IPL',
    'Chemical Peel',
    'Morpheus8',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfilePrefs();
    _refreshPremiumState();
  }

  Future<void> _refreshPremiumState() async {
    final premium = await PremiumAccess.isPremiumUser();
    final testingAvailable = await PremiumAccess.isTestingModeAvailable();
    final testingActive = await PremiumAccess.isTestingPremiumActive();
    if (!mounted) return;
    setState(() {
      _isPremiumUser = premium;
      _testingModeAvailable = testingAvailable;
      _testingPremiumActive = testingActive;
    });
  }

  Future<void> _toggleTestPremium(bool value) async {
    await PremiumAccess.setTestingPremium(value);
    await _refreshPremiumState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? 'Test Premium activated.' : 'Test Premium deactivated.',
        ),
        backgroundColor: MyApp.clinicalTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _resetPremiumToFree() async {
    await PremiumAccess.resetAllPremium();
    await _refreshPremiumState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Subscription reset to Free tier.'),
        backgroundColor: MyApp.clinicalTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadProfilePrefs() async {
    final name = await AppPrefs.getUserName();
    final ageRange = await AppPrefs.getUserAgeRange();
    final skinConcerns = await AppPrefs.getUserSkinConcerns();
    final clinic = await AppPrefs.getUserClinic();
    final procedure = await AppPrefs.getProcedureType();
    final profilePicture = await AppPrefs.getUserProfilePictureOrNull();
    final scanEntries = await AppPrefs.getScanEntries();
    final verboseDiagnostics = await AppPrefs.getVerboseDiagnosticsEnabled();
    final notificationsEnabled = await AppPrefs.getNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _savedName = name;
      _savedAgeRange = ageRange;
      _savedSkinConcerns = skinConcerns;
      _savedClinic = clinic;
      _savedProcedure = procedure;
      _savedProfilePicture = profilePicture;
      _savedScanCount = scanEntries.length;
      _lastScanAt = scanEntries.isEmpty ? null : scanEntries.first.timestamp;
      _verboseDiagnosticsEnabled = verboseDiagnostics;
      _notificationsEnabled = notificationsEnabled;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    await AppPrefs.setNotificationsEnabled(value);
    if (!mounted) return;
    setState(() => _notificationsEnabled = value);

    if (!kIsWeb) {
      try {
        await NotificationService().initialize();
        if (value) {
          final granted = await NotificationService().requestPermissions();
          if (!granted) {
            await AppPrefs.setNotificationsEnabled(false);
            if (!mounted) return;
            setState(() => _notificationsEnabled = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Notification permission was denied. You can re-enable reminders later in Settings.',
                ),
                backgroundColor: MyApp.clinicalTeal,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          await NotificationService().resyncScheduledReminders();
        } else {
          await NotificationService().cancelAllReminders();
        }
      } catch (_) {
        // Notification features are optional; never block the rest of settings
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Recovery and routine reminders enabled.'
              : 'Recovery and routine reminders disabled.',
        ),
        backgroundColor: MyApp.clinicalTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleVerboseDiagnostics(bool value) async {
    await AppPrefs.setVerboseDiagnosticsEnabled(value);
    if (!mounted) return;
    setState(() => _verboseDiagnosticsEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Verbose diagnostics enabled.'
              : 'Verbose diagnostics disabled.',
        ),
        backgroundColor: MyApp.clinicalTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ImageProvider<Object>? _avatarProvider() {
    final ref = _savedProfilePicture;
    if (ref == null || ref.isEmpty) return null;
    if (ref.startsWith('data:image') && ref.contains(',')) {
      final parts = ref.split(',');
      if (parts.length == 2) {
        try {
          return MemoryImage(base64Decode(parts[1]));
        } catch (_) {
          return null;
        }
      }
    }
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return NetworkImage(ref);
    }
    if (!ref.startsWith('/') && !ref.contains(':\\')) {
      return null;
    }
    final file = File(ref);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  String get _nameAndProcedureLabel {
    final parts = <String>[
      if (_savedName.trim().isNotEmpty) _savedName.trim(),
      if (_savedProcedure.trim().isNotEmpty) _savedProcedure.trim(),
    ];
    return parts.isEmpty ? 'No name or procedure saved' : parts.join(' • ');
  }

  Uint8List _circleCropPng(Uint8List sourceBytes) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    final side = min(decoded.width, decoded.height);
    final offsetX = (decoded.width - side) ~/ 2;
    final offsetY = (decoded.height - side) ~/ 2;
    final square = img.copyCrop(
      decoded,
      x: offsetX,
      y: offsetY,
      width: side,
      height: side,
    );

    final out = img.Image(width: side, height: side, numChannels: 4);
    final radius = side / 2;
    final center = radius;
    for (int y = 0; y < side; y++) {
      for (int x = 0; x < side; x++) {
        final dx = x - center;
        final dy = y - center;
        if ((dx * dx) + (dy * dy) <= radius * radius) {
          out.setPixel(x, y, square.getPixel(x, y));
        } else {
          out.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(out));
  }

  Future<void> _pickAndSaveProfilePicture(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 92,
      );
      if (picked == null) return;

      final rawBytes = await picked.readAsBytes();
      final croppedBytes = _circleCropPng(rawBytes);

      String storedReference;
      if (kIsWeb) {
        storedReference = 'data:image/png;base64,${base64Encode(croppedBytes)}';
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final file = File(
          '${docs.path}${Platform.pathSeparator}user_profile_picture.png',
        );
        await file.writeAsBytes(croppedBytes, flush: true);
        storedReference = file.path;
      }

      await AppPrefs.setUserProfilePicture(storedReference);
      if (!mounted) return;
      setState(() => _savedProfilePicture = storedReference);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile picture updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update profile picture. Try again.'),
        ),
      );
    }
  }

  Future<void> _showProfilePictureOptions() async {
    final textColor = MyApp.textBrown;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MyApp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Profile Picture',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: Icon(
                    Icons.photo_camera_outlined,
                    color: MyApp.goldShimmer,
                  ),
                  title: Text(
                    'Take with Camera',
                    style: TextStyle(color: textColor),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickAndSaveProfilePicture(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: MyApp.goldShimmer,
                  ),
                  title: Text(
                    'Choose from Gallery',
                    style: TextStyle(color: textColor),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _pickAndSaveProfilePicture(ImageSource.gallery);
                  },
                ),
                if ((_savedProfilePicture ?? '').trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFD64545),
                    ),
                    title: Text(
                      'Remove Current Photo',
                      style: TextStyle(color: textColor),
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await AppPrefs.removeUserProfilePicture();
                      if (!mounted) return;
                      setState(() => _savedProfilePicture = null);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile picture removed.'),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatLastScan(DateTime? dateTime) {
    if (dateTime == null) return 'No scans yet';
    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _savedName);
    final textColor = MyApp.textBrown;
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Edit Name',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.6)),
              filled: true,
              fillColor: MyApp.champagne,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updated == null) return;
    await AppPrefs.setUserName(updated);
    if (!mounted) return;
    setState(() => _savedName = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Name updated successfully.')));
  }

  Future<void> _editNameAndProcedure() async {
    final nameController = TextEditingController(text: _savedName);
    String? selectedProcedure = _savedProcedure.trim().isNotEmpty
        ? _savedProcedure
        : null;
    final textColor = MyApp.textBrown;

    final updated = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: MyApp.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                'Edit Name & Procedure',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Enter your name',
                      hintStyle: TextStyle(
                        color: textColor.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: MyApp.champagne,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  (() {
                    final items = _procedureTypes
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item,
                            child: Text(item),
                          ),
                        )
                        .toList();
                    final value = selectedProcedure;
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No options available. Add one first.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: items.any((item) => item.value == value)
                          ? value
                          : null,
                      isExpanded: true,
                      hint: const Text('Select a procedure'),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: MyApp.champagne,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: items,
                      onChanged: (v) {
                        if (v == null) return;
                        setLocalState(() => selectedProcedure = v);
                      },
                    );
                  })(),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop({
                      'name': nameController.text.trim(),
                      'procedure': selectedProcedure ?? '',
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.goldShimmer,
                    foregroundColor: textColor,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == null) return;
    final updatedName = (updated['name'] ?? '').trim();
    final updatedProcedure = (updated['procedure'] ?? '').trim();
    await AppPrefs.setUserName(updatedName);
    await AppPrefs.setTrackedProcedure(updatedProcedure);
    if (!mounted) return;
    setState(() {
      _savedName = updatedName;
      _savedProcedure = updatedProcedure;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name and procedure updated successfully.')),
    );
  }

  Future<void> _editAgeRange() async {
    var selected = _savedAgeRange.isNotEmpty
        ? _savedAgeRange
        : _ageRanges.first;
    final textColor = MyApp.textBrown;
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: MyApp.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                'Edit Age Range',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: (() {
                final items = _ageRanges
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList();
                final value = selected;
                if (items.isEmpty ||
                    !items.any((item) => item.value == value)) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No options available. Add one first.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: MyApp.champagne,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: items,
                  onChanged: (v) {
                    if (v == null) return;
                    setLocalState(() => selected = v);
                  },
                );
              })(),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.goldShimmer,
                    foregroundColor: textColor,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == null || updated.trim().isEmpty) return;
    await AppPrefs.setUserAgeRange(updated);
    if (!mounted) return;
    setState(() => _savedAgeRange = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Age range updated successfully.')),
    );
  }

  Future<void> _editSkinConcerns() async {
    final selected = _savedSkinConcerns.toSet();
    final textColor = MyApp.textBrown;
    final updated = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: MyApp.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                'Edit Main Skin Concerns',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 380,
                height: 320,
                child: ListView(
                  children: _skinConcernOptions.map((option) {
                    final explanation =
                        SkinMetricRegistry.friendlyDescriptionFor(option);
                    return CheckboxListTile(
                      value: selected.contains(option),
                      activeColor: MyApp.goldShimmer,
                      checkColor: MyApp.textBrown,
                      title: ClinicalMetricLabel(
                        label: option,
                        compact: false,
                        style: TextStyle(color: textColor, fontSize: 13),
                      ),
                      subtitle: explanation == null
                          ? null
                          : Text(
                              explanation,
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.6),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setLocalState(() {
                          if (value == true) {
                            selected.add(option);
                          } else {
                            selected.remove(option);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(selected.toList()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.goldShimmer,
                    foregroundColor: textColor,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == null) return;
    await AppPrefs.setUserSkinConcerns(updated);
    if (!mounted) return;
    setState(() => _savedSkinConcerns = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skin concerns updated successfully.')),
    );
  }

  Future<void> _editClinic() async {
    final controller = TextEditingController(text: _savedClinic);
    final textColor = MyApp.textBrown;
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Edit Preferred Clinic/Provider',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: 'Optional clinic/provider',
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.6)),
              filled: true,
              fillColor: MyApp.champagne,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updated == null) return;
    await AppPrefs.setUserClinic(updated);
    if (!mounted) return;
    setState(() => _savedClinic = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clinic/provider updated successfully.')),
    );
  }

  Future<void> _resetProfileForRetest() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Reset Profile?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will clear saved onboarding/profile fields so you can test first-time onboarding again.',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await AppPrefs.clearUserProfileForRetest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile reset. Onboarding restarted.')),
    );
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  Future<void> _clearAllDataAggressively() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Clear ALL Data?',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'This will PERMANENTLY DELETE:\n'
            '• All scan history and photos\n'
            '• All procedure tracking (Hive + AppPrefs)\n'
            '• All product tracking\n'
            '• All journal entries\n'
            '• All progress data\n'
            '• ALL database boxes\n\n'
            'This action cannot be undone!',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('DELETE ALL'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    debugPrint('🔥 User confirmed nuclear clear - executing...');

    // Execute nuclear clear
    await cancelRemindersForAllProcedures();
    await AppPrefs.clearAllDataAggressively();

    // Reset the Riverpod procedure-logs provider so no cached logs remain in
    // memory (the box is now empty on disk). Any screen watching it rebuilds.
    if (mounted) {
      ProviderScope.containerOf(
        context,
        listen: false,
      ).invalidate(procedureLogsProvider);
    }

    // Wait a moment for all async operations to complete
    await Future.delayed(const Duration(milliseconds: 500));

    // Force reload profile preferences from disk
    await _loadProfilePrefs();

    if (!mounted) return;

    // Pop back to the root route so every screen rebuilds from cleared data.
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Force full UI refresh
    setState(() {
      // This will rebuild the entire settings screen with empty data
    });

    if (!mounted) return;

    // Show success message with restart recommendation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '🔥 NUCLEAR CLEAR COMPLETE!\n'
          'All data deleted. Recommend restarting app to clear any cached data.',
        ),
        duration: const Duration(seconds: 7),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );

    debugPrint('✓ Nuclear clear UI refresh complete - recommend app restart');
  }

  /// HARD RESET — wipes EVERY persisted key + all Hive boxes, then rebuilds the
  /// whole app tree (simulated restart) so the user lands on a fully empty app.
  Future<void> _hardResetEverything() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              const Icon(Icons.dangerous, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Text(
                'Hard Reset?',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'This wipes EVERYTHING and restarts the app:\n'
            '• All scans, procedures, photos\n'
            '• All products & journals\n'
            '• Your profile & onboarding\n'
            '• Every database box\n\n'
            'You will start completely fresh. This cannot be undone.',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('HARD RESET'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    debugPrint('💣 User confirmed HARD RESET - executing...');
    await AppPrefs.hardResetEverything();

    // Allow disk writes to settle before rebuilding the tree.
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Simulated restart: rebuild the entire widget tree from scratch.
    RestartWidget.restartApp(context);
    debugPrint('💣 Hard reset complete - app tree restarted');
  }

  Future<void> _clearScanHistory() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Clear Scan History?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will remove stored AI/procedure scans, baseline links, and progress comparison pointers for testing first-run scan flow. Your skin profile and onboarding stay intact.',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await AppPrefs.clearAllScanHistoryAndBaselines();
    await _loadProfilePrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scan history and baselines cleared (dev).'),
      ),
    );

    // Force refresh any screens showing scan data
    setState(() {});
  }

  Future<void> _clearProcedureHistory() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Clear Procedure History?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This deletes all saved procedure courses and clears selected procedure tagging.',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await cancelRemindersForAllProcedures();
    await AppPrefs.clearProcedureHistory();
    final remaining = await AppPrefs.getProcedureEntries();
    debugPrint(
      'Settings clear procedure history. Remaining: ${remaining.length}',
    );
    await _loadProfilePrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Procedure history cleared.')));
  }

  Future<void> _resetWelcomeTourOnly() async {
    final textColor = MyApp.textBrown;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MyApp.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            'Reset Welcome Tour?',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This will only reset the one-time tutorial, without clearing your profile or scan data.',
            style: TextStyle(color: textColor.withValues(alpha: 0.82)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.goldShimmer,
                foregroundColor: textColor,
              ),
              child: const Text('Reset Tour'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await AppPrefs.setTourCompleted(false);
    if (!mounted) return;
    await Navigator.of(context).pushNamed('/welcome-tour');
  }

  Future<void> _editTrackedProcedure() async {
    String? selected = _savedProcedure.trim().isNotEmpty
        ? _savedProcedure
        : null;
    final textColor = MyApp.textBrown;
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: MyApp.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: Text(
                'Edit Tracked Procedure',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              content: (() {
                final items = _procedureTypes
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList();
                final value = selected;
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No options available. Add one first.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  initialValue: items.any((item) => item.value == value)
                      ? value
                      : null,
                  isExpanded: true,
                  hint: const Text('Select a procedure'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: MyApp.champagne,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: items,
                  onChanged: (v) {
                    if (v == null) return;
                    setLocalState(() => selected = v);
                  },
                );
              })(),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyApp.goldShimmer,
                    foregroundColor: textColor,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == null || updated.trim().isEmpty) return;
    await AppPrefs.setTrackedProcedure(updated);
    if (!mounted) return;
    setState(() => _savedProcedure = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tracked procedure updated successfully.')),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    final launched = await launchUrl(
      _privacyPolicyUri,
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open privacy policy link.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;
    final currentMode = MyApp.themeModeNotifier.value;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              navigator.pushReplacementNamed('/home');
            }
          },
          color: textColor,
        ),
        title: const ClinicalAppBarTitle(
          title: 'Settings',
          eyebrow: 'Patient preferences',
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ClinicalSectionHeader(
                    icon: Icons.palette_outlined,
                    title: 'Appearance',
                    eyebrow: 'Visual ambience',
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 5,
                    shadowColor: MyApp.goldShimmer.withValues(alpha: 0.22),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: MyApp.goldShimmer.withValues(alpha: 0.34),
                        width: 1.1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MyApp.goldShimmer.withValues(alpha: 0.14),
                          border: Border.all(
                            color: MyApp.goldShimmer.withValues(alpha: 0.36),
                          ),
                        ),
                        child: Icon(
                          Icons.psychology_alt_rounded,
                          color: MyApp.goldShimmer,
                        ),
                      ),
                      title: Text(
                        'Skin Scan',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Capture a photo and open your combined report',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: MyApp.goldShimmer,
                      ),
                      onTap: () => Navigator.of(context).pushNamed('/ai-coach'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                    ),
                    child: RadioGroup<ThemeMode>(
                      groupValue: currentMode,
                      onChanged: (mode) {
                        if (mode == null) return;
                        MyApp.setThemeMode(mode);
                        if (!mounted) return;
                        setState(() {});
                      },
                      child: Column(
                        children: [
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.light,
                            activeColor: MyApp.goldShimmer,
                            title: Text(
                              'Light',
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              'Blush Champagne Luxe',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: textColor.withValues(alpha: 0.1),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.dark,
                            activeColor: MyApp.goldShimmer,
                            title: Text(
                              'Dark',
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              'Charcoal Luxe Night Mode',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: textColor.withValues(alpha: 0.1),
                          ),
                          RadioListTile<ThemeMode>(
                            value: ThemeMode.system,
                            activeColor: MyApp.goldShimmer,
                            title: Text(
                              'System',
                              style: TextStyle(color: textColor),
                            ),
                            subtitle: Text(
                              'Follow device appearance',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const ClinicalSectionHeader(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    eyebrow: 'Patient identity',
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  MyApp.goldShimmer.withValues(alpha: 0.95),
                                  MyApp.champagne,
                                  MyApp.goldShimmer.withValues(alpha: 0.95),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: MyApp.goldShimmer.withValues(
                                    alpha: 0.28,
                                  ),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: MyApp.roseGold.withValues(
                                alpha: 0.2,
                              ),
                              backgroundImage: _avatarProvider(),
                              child: _avatarProvider() == null
                                  ? Icon(
                                      Icons.person,
                                      color: MyApp.goldShimmer,
                                      size: 28,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Profile Picture',
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (_savedProfilePicture ?? '').trim().isEmpty
                                      ? 'No photo yet. Add one for a personal touch.'
                                      : 'Your luxe avatar is ready.',
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showProfilePictureOptions,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        (_savedProfilePicture ?? '').trim().isEmpty
                            ? 'Add Profile Picture'
                            : 'Change Profile Picture',
                      ),
                      style: MyApp.primaryGoldButton,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.manage_accounts_outlined,
                            color: MyApp.goldShimmer,
                          ),
                          title: Text(
                            'Edit Name & Procedure',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _nameAndProcedureLabel,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editNameAndProcedure,
                        ),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        ListTile(
                          leading: Icon(Icons.edit, color: MyApp.goldShimmer),
                          title: Text(
                            'Edit My Name',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _savedName.isEmpty ? 'No name saved' : _savedName,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editName,
                        ),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        const SkincareStyleSettingsTile(),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.cake_outlined,
                            color: MyApp.goldShimmer,
                          ),
                          title: Text(
                            'Edit Age Range',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _savedAgeRange.isNotEmpty
                                ? _savedAgeRange
                                : 'Not set',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editAgeRange,
                        ),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        ListTile(
                          leading: Icon(Icons.tune, color: MyApp.goldShimmer),
                          title: Text(
                            'Edit Main Skin Concerns',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _savedSkinConcerns.isNotEmpty
                                ? _savedSkinConcerns.take(2).join(', ')
                                : 'Not set',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editSkinConcerns,
                        ),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.local_hospital_outlined,
                            color: MyApp.goldShimmer,
                          ),
                          title: Text(
                            'Edit Preferred Clinic/Provider',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _savedClinic.isNotEmpty ? _savedClinic : 'Optional',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editClinic,
                        ),
                        Divider(
                          height: 1,
                          color: textColor.withValues(alpha: 0.1),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.medical_services_outlined,
                            color: MyApp.goldShimmer,
                          ),
                          title: Text(
                            'Edit Tracked Procedure',
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _savedProcedure.isEmpty
                                ? 'No procedure saved'
                                : _savedProcedure,
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.72),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: textColor.withValues(alpha: 0.6),
                          ),
                          onTap: _editTrackedProcedure,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const ClinicalSectionHeader(
                    icon: Icons.insights_outlined,
                    title: 'Activity & Insights',
                    eyebrow: 'Usage overview',
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.insights_outlined,
                        color: MyApp.goldShimmer,
                      ),
                      title: Text(
                        'Scan History',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Scans: $_savedScanCount • Last: ${_formatLastScan(_lastScanAt)}',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.14),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.settings, color: MyApp.goldShimmer),
                      title: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'How your skin data is handled',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                      trailing: Icon(
                        Icons.open_in_new,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                      onTap: _openPrivacyPolicy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: MyApp.surface,
                    elevation: 2,
                    shadowColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: MyApp.goldShimmer.withValues(alpha: 0.22),
                        width: 0.8,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.health_and_safety_outlined,
                        color: MyApp.goldShimmer,
                      ),
                      title: Text(
                        'Legal',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Terms, privacy, and license documents',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                      onTap: () => Navigator.of(context).pushNamed('/legal'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const ClinicalSectionHeader(
                    icon: Icons.shield_outlined,
                    title: 'Data & Reset',
                    eyebrow: 'Account maintenance',
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _resetProfileForRetest,
                      icon: Icon(Icons.restart_alt, color: MyApp.goldShimmer),
                      label: Text(
                        'Reset Profile (QA Retest)',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: MyApp.roseGold.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearScanHistory,
                      icon: Icon(
                        Icons.delete_sweep_outlined,
                        color: MyApp.goldShimmer,
                      ),
                      label: Text(
                        'Clear scan history (dev)',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: MyApp.roseGold.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearProcedureHistory,
                      icon: Icon(
                        Icons.folder_delete_outlined,
                        color: MyApp.goldShimmer,
                      ),
                      label: Text(
                        'Clear Procedure History',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: MyApp.roseGold.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _clearAllDataAggressively,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text(
                        '🔥 Clear ALL Data (Nuclear)',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: Colors.red.withValues(alpha: 0.45),
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _hardResetEverything,
                      icon: const Icon(Icons.restart_alt, color: Colors.white),
                      label: const Text(
                        '💣 Hard Reset (Wipe & Restart)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade900,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _resetWelcomeTourOnly,
                        icon: Icon(
                          Icons.auto_awesome_motion_outlined,
                          color: MyApp.goldShimmer,
                        ),
                        label: Text(
                          'Reset Welcome Tour Only (Debug)',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: MyApp.roseGold.withValues(alpha: 0.45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const ClinicalSectionHeader(
                    icon: Icons.notifications_active_outlined,
                    title: 'Reminders',
                    eyebrow: 'Local check-ins',
                  ),
                  const SizedBox(height: 14),
                  _buildReminderCard(textColor),
                  const SizedBox(height: 28),
                  const ClinicalSectionHeader(
                    icon: Icons.workspace_premium_outlined,
                    title: 'Subscription',
                    eyebrow: 'Membership status',
                  ),
                  const SizedBox(height: 14),
                  _buildSubscriptionCard(textColor),
                  if (_testingModeAvailable) ...[
                    const SizedBox(height: 28),
                    const ClinicalSectionHeader(
                      icon: Icons.science_outlined,
                      title: 'Developer & Testing',
                      eyebrow: 'Subscription tools',
                    ),
                    const SizedBox(height: 14),
                    _buildTestingCard(textColor),
                  ],
                  if (kDebugMode) ...[
                    const SizedBox(height: 28),
                    const ClinicalSectionHeader(
                      icon: Icons.bug_report_outlined,
                      title: 'Diagnostics',
                      eyebrow: 'Debug logging',
                    ),
                    const SizedBox(height: 14),
                    _buildDiagnosticsCard(textColor),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.clinicalSlate.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _notificationsEnabled,
        onChanged: _toggleNotifications,
        activeThumbColor: MyApp.clinicalTeal,
        activeTrackColor: MyApp.clinicalTeal.withValues(alpha: 0.35),
        title: Text(
          'Recovery + routine reminders',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: textColor,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          'Local alerts for upcoming treatment windows and peptide routines. '
          'This is off by default until you opt in.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard(Color textColor) {
    final isPremium = _isPremiumUser;
    final badgeColor = isPremium ? MyApp.roseGold : MyApp.clinicalSlate;
    final badgeText = isPremium ? 'PREMIUM' : 'FREE';
    final subtitle = isPremium
        ? 'You have full access to every clinical feature, unlimited scans, '
              'and unlimited Professional Reports.'
        : 'Basic tracking with limited scans. Upgrade to unlock unlimited '
              'scans, the full AI Recovery Coach, and provider-ready reports.';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isPremium ? MyApp.roseGold : MyApp.clinicalSlate).withValues(
            alpha: isPremium ? 0.40 : 0.18,
          ),
          width: isPremium ? 1.0 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.person_outline_rounded,
                color: badgeColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Current plan',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: isPremium
                      ? LinearGradient(
                          colors: [MyApp.goldShimmer, MyApp.roseGold],
                        )
                      : null,
                  color: isPremium
                      ? null
                      : MyApp.clinicalSlate.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: isPremium
                      ? null
                      : Border.all(
                          color: MyApp.clinicalSlate.withValues(alpha: 0.30),
                          width: 0.6,
                        ),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: isPremium ? Colors.white : MyApp.clinicalSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: textColor.withValues(alpha: 0.78),
            ),
          ),
          if (!isPremium) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(
                    context,
                  ).pushNamed('/paywall');
                  if (result == true) await _refreshPremiumState();
                },
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text(
                  'Upgrade to Premium · ${PremiumPlans.monthlyPriceDisplay}/mo',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyApp.clinicalNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestingCard(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.clinicalSlate.withValues(alpha: 0.22),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _testingPremiumActive,
            onChanged: _toggleTestPremium,
            activeThumbColor: MyApp.clinicalTeal,
            activeTrackColor: MyApp.clinicalTeal.withValues(alpha: 0.35),
            title: Text(
              'Test Premium',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textColor,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              'Instantly unlock all premium features locally — '
              'no payment required.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
          ),
          const Divider(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetPremiumToFree,
              icon: Icon(Icons.restart_alt_rounded, color: MyApp.clinicalSlate),
              label: Text(
                'Reset to Free Tier',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(
                  color: MyApp.clinicalSlate.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.clinicalSlate.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _verboseDiagnosticsEnabled,
        onChanged: _toggleVerboseDiagnostics,
        activeThumbColor: MyApp.clinicalTeal,
        activeTrackColor: MyApp.clinicalTeal.withValues(alpha: 0.35),
        title: Text(
          'Verbose diagnostics',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: textColor,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          'Shows detailed internal debug logs in the terminal.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textColor.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

// Paywall screen implementation
