// lib/screens/skin_quiz_screen.dart - IMPROVED VERSION
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';

class SkinQuizScreen extends StatefulWidget {
  const SkinQuizScreen({super.key});

  @override
  State<SkinQuizScreen> createState() => _SkinQuizScreenState();
}

class _SkinQuizScreenState extends State<SkinQuizScreen> {
  int _currentStep = 0; // 0 = Skin Type, 1 = Concerns, 2 = Summary

  String? selectedSkinType;
  List<String> selectedConcerns = [];

  final List<String> skinTypes = [
    'Dry',
    'Oily',
    'Combination',
    'Sensitive',
    'Normal',
  ];

  final List<String> allConcerns = [
    'Acne',
    'Redness',
    'Pigmentation',
    'Wrinkles',
    'Dryness',
    'Sensitivity',
    'Pores',
    'Oiliness',
    'Dullness',
    'Texture',
    'Uneven Tone',
    'Fine Lines',
    'Dark Spots',
    'Rosacea',
    'Blackheads',
  ];

  void _nextStep() {
    if (_currentStep == 0 && selectedSkinType == null) return;
    if (_currentStep == 1 && selectedConcerns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one concern')),
      );
      return;
    }
    setState(() => _currentStep++);
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Skin Profile Quiz',
          eyebrow: 'Step ${_currentStep + 1} of 3',
          color: MyApp.clinicalNavy,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.clinicalNavy,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress bar
              LinearProgressIndicator(
                value: (_currentStep + 1) / 3,
                backgroundColor: Colors.grey.shade200,
                color: MyApp.roseGold,
                minHeight: 6,
              ),
              const SizedBox(height: 32),

              // Step Content
              Expanded(child: _buildStepContent()),

              // Navigation Buttons
              Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _currentStep == 2
                          ? () {
                              Navigator.pop(context, {
                                'skinType': selectedSkinType,
                                'concerns': selectedConcerns,
                              });
                            }
                          : _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.roseGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _currentStep == 2 ? 'Save My Skin Profile' : 'Continue',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    if (_currentStep == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What is your skin type?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Choose the one that best describes your skin overall.'),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: skinTypes.map((type) {
              return ChoiceChip(
                label: Text(type, style: const TextStyle(fontSize: 16)),
                selected: selectedSkinType == type,
                onSelected: (selected) {
                  setState(() => selectedSkinType = selected ? type : null);
                },
                selectedColor: MyApp.roseGold.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              );
            }).toList(),
          ),
        ],
      );
    } else if (_currentStep == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What are your main skin concerns?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('You can select multiple.'),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: allConcerns.map((concern) {
                  return FilterChip(
                    label: Text(concern),
                    selected: selectedConcerns.contains(concern),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedConcerns.add(concern);
                        } else {
                          selectedConcerns.remove(concern);
                        }
                      });
                    },
                    backgroundColor: Colors.white,
                    selectedColor: MyApp.roseGold.withValues(alpha: 0.3),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      );
    } else {
      // Summary Step
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review Your Skin Profile',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skin Type',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    selectedSkinType ?? 'Not selected',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Main Concerns',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    selectedConcerns.isEmpty
                        ? 'None'
                        : selectedConcerns.join(', '),
                    style: const TextStyle(fontSize: 17),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'This will help the AI build a better routine for you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    }
  }
}
