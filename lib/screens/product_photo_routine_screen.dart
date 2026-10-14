import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../features/ai_coach/presentation/widgets/shelf_scanner_modal.dart';
import '../services/ai_llm_service.dart';
import '../utils/app_prefs.dart';
import '../utils/product_routine_builder.dart';
import '../utils/upload_gate.dart';

/// Prompt for reading skincare products from a shelf / product photo and
/// laying out a simple morning and evening routine.
const String productPhotoRoutineSystemPrompt =
    'You identify skincare products from a photo of their packaging and '
    'arrange them into a simple daily routine. Only list products you can '
    'actually see. Do not diagnose skin conditions or give medical advice.';

const String productPhotoRoutineUserPrompt =
    'List the skincare products visible in this photo, then arrange them '
    'into a morning and an evening routine. Reply in exactly this format:\n'
    'Products:\n- <brand and product name>\n'
    'Morning routine:\n1. <product> - <one short reason>\n'
    'Evening routine:\n1. <product> - <one short reason>';

typedef ProductPhotoPicker = Future<XFile?> Function(BuildContext context);
typedef ProductPhotoReader = Future<String> Function(XFile photo);

/// Take or pick a photo of skincare products, read them with AI, and save
/// a morning / evening routine as the active AI routine (shown on the
/// Routines screen). Products can also be typed in when AI photo reading
/// isn't available.
class ProductPhotoRoutineScreen extends StatefulWidget {
  const ProductPhotoRoutineScreen({super.key, this.pickPhoto, this.readPhoto});

  /// Defaults to the existing shelf scanner (camera or gallery).
  final ProductPhotoPicker? pickPhoto;

  /// Defaults to Gemini Vision through AiLlmService.
  final ProductPhotoReader? readPhoto;

  @override
  State<ProductPhotoRoutineScreen> createState() =>
      _ProductPhotoRoutineScreenState();
}

class _ProductPhotoRoutineScreenState extends State<ProductPhotoRoutineScreen> {
  final _manualController = TextEditingController();
  bool _busy = false;
  String? _message;
  String _source = 'product_photo';
  List<String> _products = const [];
  List<String> _morning = const [];
  List<String> _evening = const [];

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<String> _defaultReadPhoto(XFile photo) {
    if (kIsWeb) {
      throw const AiLlmConfigurationException(
        'Reading product photos is not available on web.',
      );
    }
    return const AiLlmService().analyzeSkinWithImage(
      imageFile: File(photo.path),
      systemPrompt: productPhotoRoutineSystemPrompt,
      userPrompt: productPhotoRoutineUserPrompt,
    );
  }

  Future<void> _pickAndRead() async {
    final picker = widget.pickPhoto ?? showShelfScannerModal;
    final photo = await picker(context);
    if (photo == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final reply = await (widget.readPhoto ?? _defaultReadPhoto)(photo);
      final steps = extractAmPmRoutineSteps(reply);
      final products = extractDetectedProducts(reply);
      if (!mounted) return;
      setState(() {
        _source = 'product_photo';
        _products = products;
        _morning = steps.morning;
        _evening = steps.evening;
        _message = steps.morning.isEmpty && steps.evening.isEmpty
            ? 'No routine could be read from that photo. Try a clearer '
                  'photo, or type your products below.'
            : null;
      });
    } on UploadGateBlockedException {
      if (!mounted) return;
      setState(
        () => _message =
            'Reading product photos needs Premium or a scan credit. Type '
            'your products below instead.',
      );
    } on AiLlmConfigurationException {
      if (!mounted) return;
      setState(
        () => _message =
            'AI photo reading isn\'t set up in this build. Type your '
            'products below instead.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message =
            'Couldn\'t read that photo ($error). Type your products below '
            'instead.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _buildFromTypedProducts() {
    final names = _manualController.text
        .split(RegExp(r'[\n,]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final steps = buildAmPmStepsFromProductNames(names);
    setState(() {
      _source = 'product_list';
      _products = names;
      _morning = steps.morning;
      _evening = steps.evening;
      _message = names.isEmpty ? 'Type at least one product.' : null;
    });
  }

  Future<void> _save() async {
    await AppPrefs.saveActiveAiRoutine(
      activeAiRoutinePayload(
        morningSteps: _morning,
        eveningSteps: _evening,
        detectedProducts: _products,
        source: _source,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Routine saved to Routines')));
    Navigator.of(context).maybePop();
  }

  Widget _stepList(String title, List<String> steps) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      if (steps.isEmpty) const Text('No steps'),
      for (var i = 0; i < steps.length; i++) Text('${i + 1}. ${steps[i]}'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final hasRoutine = _morning.isNotEmpty || _evening.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Products → AI routine')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Take or choose a photo of your skincare products. AI reads the '
            'packaging and builds a morning and evening routine you can '
            'save. The photo is sent to Google Gemini to identify the '
            'products.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('product_photo_pick_button'),
            onPressed: _busy ? null : _pickAndRead,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take or choose a product photo'),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, key: const ValueKey('product_photo_message')),
          ],
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('product_list_field'),
            controller: _manualController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Or type your products (one per line)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('product_list_build_button'),
            onPressed: _busy ? null : _buildFromTypedProducts,
            child: const Text('Build routine from my list'),
          ),
          if (_products.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Products',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final product in _products) Text('• $product'),
          ],
          if (hasRoutine) ...[
            const SizedBox(height: 24),
            _stepList('Morning', _morning),
            const SizedBox(height: 16),
            _stepList('Evening', _evening),
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('product_routine_save_button'),
              onPressed: _save,
              child: const Text('Save as my routine'),
            ),
          ],
        ],
      ),
    );
  }
}
