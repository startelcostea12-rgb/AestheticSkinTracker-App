// Text Note Dialog
void _showTextNoteDialog(int globalIdx, {ScarJournalNote? editing}) {
  final ctrl = TextEditingController(text: editing?.text ?? '');
  final isEdit = editing != null;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 28,
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: MyApp.roseGold, size: 28),
              const SizedBox(width: 10),
              Text(
                isEdit ? 'Edit Note' : 'Add Text Note',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: MyApp.roseGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 500,
            decoration: InputDecoration(
              hintText:
                  'e.g. Applied silicone gel today, skin felt less itchy...',
              hintStyle: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.40),
                fontSize: 13.5,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: MyApp.roseGold.withValues(alpha: 0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: MyApp.roseGold, width: 1.8),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(
                isEdit ? Icons.save_outlined : Icons.add_circle_outline,
              ),
              label: Text(isEdit ? 'Save Changes' : 'Add Note'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () {
                final text = ctrl.text.trim();
                if (text.isEmpty) return;
                setState(() {
                  final entry = _entries[globalIdx];
                  List<ScarJournalNote> updated;
                  if (isEdit) {
                    updated = entry.notes
                        .map(
                          (n) => n.id == editing.id ? n.copyWithText(text) : n,
                        )
                        .toList();
                  } else {
                    final newNote = ScarJournalNote(
                      id: '${DateTime.now().millisecondsSinceEpoch}',
                      createdAt: DateTime.now(),
                      text: text,
                    );
                    updated = [...entry.notes, newNote];
                  }
                  _entries[globalIdx] = entry.copyWith(notes: updated);
                });
                _saveEntries();
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

void _deleteNote(int globalIdx, String noteId) {
  setState(() {
    final entry = _entries[globalIdx];
    _entries[globalIdx] = entry.copyWith(
      notes: entry.notes.where((n) => n.id != noteId).toList(),
    );
  });
  _saveEntries();
}

// Per-entry journal section widget
Widget _buildEntryJournalSection(ScarPhotoEntry entry, int globalIdx) {
  final legacyTranscript = (entry.transcript?.trim().isNotEmpty ?? false)
      ? entry.transcript!.trim()
      : null;
  final hasAny = legacyTranscript != null || entry.notes.isNotEmpty;
  final totalCount = (legacyTranscript != null ? 1 : 0) + entry.notes.length;

  return StatefulBuilder(
    builder: (ctx, setOuter) {
      bool expanded = false;
      return StatefulBuilder(
        builder: (ctx2, setExpanded) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note_rounded, size: 15),
                    label: const Text('Add Text Note'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MyApp.roseGold,
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _showTextNoteDialog(globalIdx),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.mic_none_rounded, size: 15),
                    label: const Text('Voice Note'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MyApp.roseGold,
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () =>
                        _showVoiceJournalModal(globalEntryIndex: globalIdx),
                  ),
                ),
              ],
            ),
            if (hasAny) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setExpanded(() => expanded = !expanded),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: MyApp.roseGold.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        totalCount == 1
                            ? '1 journal entry'
                            : '$totalCount journal entries',
                        style: TextStyle(
                          fontSize: 12,
                          color: MyApp.roseGold.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOut,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          if (legacyTranscript != null)
                            _noteChip(
                              text: legacyTranscript,
                              date: entry.date,
                              isVoice: true,
                              onEdit: null,
                              onDelete: null,
                            ),
                          ...entry.notes.map(
                            (note) => _noteChip(
                              text: note.text,
                              date: note.createdAt,
                              isVoice: note.isVoice,
                              onEdit: note.isVoice
                                  ? null
                                  : () => _showTextNoteDialog(
                                      globalIdx,
                                      editing: note,
                                    ),
                              onDelete: () => _deleteNote(globalIdx, note.id),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _noteChip({
  required String text,
  required DateTime date,
  required bool isVoice,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: isVoice
          ? MyApp.roseGold.withValues(alpha: 0.06)
          : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isVoice
            ? MyApp.roseGold.withValues(alpha: 0.22)
            : Colors.grey.shade200,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isVoice ? Icons.mic_none_rounded : Icons.notes_rounded,
          size: 14,
          color: isVoice
              ? MyApp.roseGold.withValues(alpha: 0.7)
              : MyApp.textBrown.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: MyApp.textBrown.withValues(alpha: 0.78),
                  fontStyle: isVoice ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_fmt(date)}  -  ${isVoice ? "Voice" : "Text"}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: MyApp.textBrown.withValues(alpha: 0.38),
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.edit_outlined,
                size: 14,
                color: MyApp.textBrown.withValues(alpha: 0.4),
              ),
            ),
          ),
        if (onDelete != null)
          GestureDetector(
            onTap: onDelete,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: Colors.red.shade300,
              ),
            ),
          ),
      ],
    ),
  );
}
