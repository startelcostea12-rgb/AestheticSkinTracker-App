import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../app_theme.dart';
import '../models/procedure.dart';
import '../widgets/adaptive_camera_guide_visuals.dart';
import '../widgets/app_brand_title.dart';
import '../widgets/clinical_section_header.dart';
import 'camera_screen.dart';

class ProcedureCameraGuideScreen extends StatelessWidget {
  const ProcedureCameraGuideScreen({super.key, required this.procedure});

  final Procedure procedure;

  ProcedureCameraGuideType get _guideType =>
      procedureCameraGuideType(procedure.type);

  bool get _isBodyGuide => _guideType == ProcedureCameraGuideType.body;

  String get _guideTitle {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return 'Facial Scan Guide';
      case ProcedureCameraGuideType.body:
        return 'Body Scan Guide';
      case ProcedureCameraGuideType.general:
        return 'Progress Scan Guide';
    }
  }

  String get _guideInstruction {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return 'Front view, neutral expression, left profile, right profile. Keep the same distance and lighting as your previous photos.';
      case ProcedureCameraGuideType.body:
        return 'Stand straight with arms relaxed. Show front, side, and back views of the treated area.';
      case ProcedureCameraGuideType.general:
        return 'Frame the treatment area clearly and capture matching angles each time so progress and before-and-after comparisons stay reliable.';
    }
  }

  List<String> get _captureAngles {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return const [
          'Front view',
          'Left profile',
          'Right profile',
          '45-degree views',
        ];
      case ProcedureCameraGuideType.body:
        return const ['Front view', 'Side view', 'Back view', 'Arms relaxed'];
      case ProcedureCameraGuideType.general:
        return const [
          'Primary view',
          'Secondary angle',
          'Consistent framing',
          'Same lighting',
        ];
    }
  }

  String get _exampleGoodCaption {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return 'Centered face, neutral expression, and matching distance for repeatable facial metrics.';
      case ProcedureCameraGuideType.body:
        return 'Straight posture, full treated area visible, and balanced framing across front, side, and back views.';
      case ProcedureCameraGuideType.general:
        return 'Consistent framing and even light make progress comparisons easier to trust.';
    }
  }

  String get _exampleBadCaption {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return 'Tilted framing, changed distance, or uneven light makes profile and skin-age comparisons unreliable.';
      case ProcedureCameraGuideType.body:
        return 'Twisting, cropped contours, or inconsistent stance hides real changes and distorts body metrics.';
      case ProcedureCameraGuideType.general:
        return 'Cropping, blur, or changing your angle reduces the reliability of before-and-after tracking.';
    }
  }

  List<String> get _preflightChecklist {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return const [
          'Keep your expression neutral and avoid smiling or squinting.',
          'Center your forehead, eyes, nose, and chin fully in frame.',
          'Use the same room lighting and camera distance as your last scan.',
        ];
      case ProcedureCameraGuideType.body:
        return const [
          'Keep your posture upright and camera height consistent with previous scans.',
          'Wear similar fitted clothing or expose the same treatment area each time.',
          'Use even light and a plain background so contour changes stay readable.',
        ];
      case ProcedureCameraGuideType.general:
        return const [
          'Keep the treatment area fully visible with minimal cropping.',
          'Match the same angle, distance, and lighting as your last scan.',
          'Hold the camera steady so your metrics compare cleanly over time.',
        ];
    }
  }

  IconData get _guideIcon {
    switch (_guideType) {
      case ProcedureCameraGuideType.facial:
        return Icons.face_retouching_natural;
      case ProcedureCameraGuideType.body:
        return Icons.accessibility_new_rounded;
      case ProcedureCameraGuideType.general:
        return Icons.camera_alt_outlined;
    }
  }

  Future<void> _continueToCamera(BuildContext context) async {
    final didCapture = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(procedure: procedure)),
    );
    if (!context.mounted) return;
    if (didCapture == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return CameraScreen(procedure: procedure);
    }

    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: MyApp.goldShimmer),
                  ),
                  const Expanded(
                    child: AppBrandTitle(height: 44, maxWidth: 220),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_guideIcon, color: MyApp.goldShimmer),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _guideTitle,
                                style: MyApp.sectionTitleStyle(
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                procedure.type,
                                style: TextStyle(
                                  color: textColor.withValues(alpha: 0.68),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _guideInstruction,
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            color: MyApp.goldShimmer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Match the same angle, distance, and lighting as your last scan for accurate tracking and metrics.',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    AdaptiveCameraOutline(
                      guideType: _guideType,
                      height: _isBodyGuide ? 360 : 320,
                      angleChips: _captureAngles,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.camera_outlined,
                title: 'Capture These Angles',
                eyebrow: 'Photography protocol',
              ),
              const SizedBox(height: 10),
              _buildChecklistCard(
                title: 'Capture These Angles',
                items: _captureAngles,
              ),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.checklist_rounded,
                title: 'Before You Continue',
                eyebrow: 'Preflight checklist',
              ),
              const SizedBox(height: 10),
              _buildChecklistCard(
                title: 'Before You Continue',
                items: _preflightChecklist,
              ),
              const SizedBox(height: 18),
              const ClinicalSectionHeader(
                icon: Icons.compare_outlined,
                title: 'Reference Examples',
                eyebrow: 'Good vs. avoid',
              ),
              const SizedBox(height: 10),
              _buildExamplesCard(),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => _continueToCamera(context),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Got it - Open Camera'),
                style: MyApp.primaryGoldButton,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExamplesCard() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: MyApp.surface,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: MyApp.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good Example vs Bad Example',
              style: TextStyle(
                color: MyApp.textBrown,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Use the strong framing example every time so metrics, skin age, and before-and-after comparisons stay consistent.',
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.78),
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CameraExampleImageCard(
                    guideType: _guideType,
                    title: 'Good example',
                    caption: _exampleGoodCaption,
                    isGood: true,
                  ),
                  const SizedBox(width: 12),
                  CameraExampleImageCard(
                    guideType: _guideType,
                    title: 'Bad example',
                    caption: _exampleBadCaption,
                    isGood: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistCard({
    required String title,
    required List<String> items,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: MyApp.surface,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: MyApp.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: MyApp.textBrown,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: MyApp.goldShimmer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
