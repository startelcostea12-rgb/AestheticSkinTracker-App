// "Note for this scan" on the AI scan results: optional free text saved
// with the scan (see saveScanNote).

import 'package:flutter/material.dart';

import '../utils/scan_note.dart';

class ScanNoteField extends StatefulWidget {
  const ScanNoteField({super.key, required this.scanId, this.initialNote});

  final String scanId;
  final String? initialNote;

  static const String label = 'Note for this scan';

  @override
  State<ScanNoteField> createState() => _ScanNoteFieldState();
}

class _ScanNoteFieldState extends State<ScanNoteField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await saveScanNote(
      scanId: widget.scanId,
      note: _controller.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !saved
              ? 'Could not find this scan to save the note.'
              : _controller.text.trim().isEmpty
              ? 'Note cleared'
              : 'Note saved',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('scan_note_field'),
          controller: _controller,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: ScanNoteField.label,
            hintText: 'Optional',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            key: const ValueKey('scan_note_save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save note'),
          ),
        ),
      ],
    );
  }
}
