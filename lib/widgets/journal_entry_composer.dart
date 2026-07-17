// lib/widgets/journal_entry_composer.dart
//
// Reusable bottom-sheet composer for creating a JournalEntry.
// Used by the active skincare details screen and the procedure profile screen.

import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../models/journal_entry.dart';

const List<String> _moodEmojis = ['😞', '😐', '🙂', '😊', '🥰'];

/// Opens a bottom-sheet composer pre-filled with [context] (e.g. product or
/// procedure name) and returns a new [JournalEntry] when the user saves.
///
/// Returns null if the user cancels.
Future<JournalEntry?> showJournalEntryComposer({
  required BuildContext context,
  required String contextTitle,
  String? contextSubtitle,
  bool showSwelling = false,
}) {
  return showModalBottomSheet<JournalEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _JournalComposerSheet(
      contextTitle: contextTitle,
      contextSubtitle: contextSubtitle,
      showSwelling: showSwelling,
    ),
  );
}

class _JournalComposerSheet extends StatefulWidget {
  const _JournalComposerSheet({
    required this.contextTitle,
    this.contextSubtitle,
    this.showSwelling = false,
  });

  final String contextTitle;
  final String? contextSubtitle;
  final bool showSwelling;

  @override
  State<_JournalComposerSheet> createState() => _JournalComposerSheetState();
}

class _JournalComposerSheetState extends State<_JournalComposerSheet> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  int _mood = 3;
  int _swelling = 1;
  String? _imagePath;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image != null && mounted) {
        setState(() => _imagePath = image.path);
      }
    } catch (_) {
      // Fall back silently — picker may not be available on all platforms.
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: MyApp.roseGold),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: MyApp.roseGold,
              ),
              title: const Text(
                kIsWeb ? 'Upload from device' : 'Choose from Gallery',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _imagePath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final path = _imagePath!;
    Widget img;
    if (kIsWeb || path.startsWith('http')) {
      img = Image.network(path, fit: BoxFit.cover);
    } else {
      img = Image.file(File(path), fit: BoxFit.cover);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: 72, height: 72, child: img),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Material(
            color: Colors.red,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _imagePath = null),
              child: const SizedBox(
                width: 22,
                height: 22,
                child: Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a quick note before saving.')),
      );
      return;
    }
    setState(() => _saving = true);
    final title = _titleController.text.trim();
    final entry = JournalEntry(
      date: DateTime.now(),
      title: title.isEmpty ? 'Journal Entry' : title,
      content: content,
      moodRating: _mood,
      attachedImagePath: _imagePath,
      swellingLevel: widget.showSwelling ? _swelling : null,
    );
    if (!mounted) return;
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: MyApp.roseGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.edit_note_rounded,
                      color: MyApp.roseGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Journal Entry',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.contextTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: MyApp.textBrown.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.contextSubtitle != null &&
                            widget.contextSubtitle!.isNotEmpty)
                          Text(
                            widget.contextSubtitle!,
                            style: TextStyle(
                              fontSize: 12,
                              color: MyApp.textBrown.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _fieldLabel('How does your skin feel?'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (i) {
                  final selected = _mood == i + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _mood = i + 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected
                            ? MyApp.roseGold.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _moodEmojis[i],
                        style: TextStyle(fontSize: selected ? 36 : 28),
                      ),
                    ),
                  );
                }),
              ),
              if (widget.showSwelling) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    _fieldLabel('Swelling level'),
                    const Spacer(),
                    Text(
                      '${JournalEntry.swellingLabelFor(_swelling)} ($_swelling/10)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MyApp.roseGold,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _swelling.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: MyApp.roseGold,
                  label: _swelling.toString(),
                  onChanged: (v) => setState(() => _swelling = v.round()),
                ),
              ],
              const SizedBox(height: 18),
              _fieldLabel('Title', optional: true),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                decoration: _decoration(hint: 'e.g. Day 3 update'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Notes', required: true),
              const SizedBox(height: 6),
              TextField(
                controller: _contentController,
                maxLines: 6,
                decoration: _decoration(
                  hint:
                      'How does your skin feel today? Any changes you noticed?',
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Attach photo', optional: true),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showPhotoSourceSheet,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      if (_imagePath != null)
                        _buildImagePreview()
                      else
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: MyApp.champagne.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: MyApp.roseGold.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(
                            Icons.add_a_photo_outlined,
                            color: MyApp.roseGold,
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _imagePath != null
                              ? 'Tap to change • tap ✕ to remove'
                              : 'Take a photo or choose from your gallery',
                          style: TextStyle(
                            fontSize: 13,
                            color: MyApp.textBrown.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.textBrown,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.roseGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 4,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save entry',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
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

  Widget _fieldLabel(
    String label, {
    bool required = false,
    bool optional = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: MyApp.textBrown,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
          ),
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'optional',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: MyApp.textBrown.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: MyApp.textBrown.withValues(alpha: 0.4),
        fontSize: 13.5,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: MyApp.roseGold, width: 1.5),
      ),
    );
  }
}
