import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../data/photo_store.dart';
import 'format.dart';
import 'theme.dart';

/// A transaction's details: its category (optionally for everything from the
/// same payee), photos kept with it, and delete.
Future<void> showCategorySheet(BuildContext context, AppDatabase db, ActivityResult row) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation
        : const AnimationStyle(duration: Duration(milliseconds: 240), reverseDuration: Duration(milliseconds: 200)),
    backgroundColor: const Color(0xFF122022),
    builder: (_) => _CategorySheet(db: db, row: row),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.db, required this.row});
  final AppDatabase db;
  final ActivityResult row;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  var _forPayee = true;

  Future<void> _pick(int? categoryId) async {
    final row = widget.row;
    if (_forPayee && row.t.payeeId != null) {
      final count = await widget.db.payeeChangeCount(row.t);
      if (!mounted) return;
      final rows = count == 1 ? '1 transaction' : '$count transactions';
      final payee = row.payee ?? 'this payee';
      final apply = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(categoryId == null ? 'Move $rows to Unsorted?' : 'Apply category to $rows?'),
        content: Text(categoryId == null
            ? '$payee will no longer have a default category.'
            : 'This also sets the default category for $payee.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ));
      if (apply != true || !mounted) return;
    }
    await widget.db.setCategory(widget.row.t, categoryId, forPayee: _forPayee);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final t = widget.row.t;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text('${widget.row.payee ?? 'Unknown'} · ${inr(t.amount)} · ${dayLabel(t.txnDate)}\n\n'
            'This cannot be undone. A later sync or import can add it again if its SMS, email or statement '
            'row is read again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    for (final name in await widget.db.deleteTxn(t.id)) {
      await photoStore.remove(name);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 2000);
    if (picked == null) return;
    final name = await photoStore.save(picked.path);
    await widget.db.addAttachment(widget.row.t.id, name);
  }

  Future<void> _openPhoto(Attachment photo) async {
    final file = await photoStore.file(photo.fileName);
    if (!mounted) return;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain))),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context, false),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Delete photo',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => Navigator.pop(context, true),
              ),
            ),
          ],
        ),
      ),
    );
    if (remove != true) return;
    await widget.db.deleteAttachment(photo.id);
    await photoStore.remove(photo.fileName);
  }

  Widget _photos() => StreamBuilder<List<Attachment>>(
        stream: widget.db.watchAttachments(widget.row.t.id),
        builder: (context, snap) {
          final photos = snap.data ?? const <Attachment>[];
          return SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final p in photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _openPhoto(p),
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder(
                        future: photoStore.file(p.fileName),
                        builder: (context, f) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: f.hasData
                              ? Image.file(f.data!, width: 76, height: 76, fit: BoxFit.cover, cacheWidth: 228)
                              : const SizedBox(width: 76, height: 76),
                        ),
                      ),
                    ),
                  ),
                _addButton(Icons.photo_camera_outlined, 'Camera', () => _addPhoto(ImageSource.camera)),
                const SizedBox(width: 8),
                _addButton(Icons.photo_library_outlined, 'Gallery', () => _addPhoto(ImageSource.gallery)),
              ],
            ),
          );
        },
      );

  Widget _addButton(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, color: teal), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 12))],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.row.t;
    final text = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => StreamBuilder<List<Category>>(
        stream: widget.db.watchCategories(),
        builder: (context, snap) {
          final cats = snap.data ?? const <Category>[];
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(widget.row.payee ?? 'Unknown', style: text.titleLarge),
              Text(
                  '${t.direction == 'CR' ? 'Received' : 'Paid'} ${inr(t.amount)} · ${dayLabel(t.txnDate)}'
                  '${timeLabel(t.txnTime) == null ? '' : ', ${timeLabel(t.txnTime)}'}',
                  style: text.bodyMedium?.copyWith(color: Colors.white60)),
              if (t.rawText != null) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Original transaction alert'),
                  children: [SelectableText(t.rawText!)],
                ),
              ],
              const SizedBox(height: 16),
              Text('Photos', style: text.labelLarge),
              Text('A bill or what you bought, to remember what this was. Kept only on this phone.',
                  style: text.bodySmall?.copyWith(color: Colors.white54)),
              const SizedBox(height: 8),
              _photos(),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _forPayee,
                onChanged: (v) => setState(() => _forPayee = v),
                title: const Text('Apply to everything from this payee'),
                subtitle: const Text('Rows you labelled one by one are kept'),
              ),
              const Divider(),
              for (final c in cats)
                _option(c.name, c.id, selected: c.id == t.categoryId),
              _option('Unsorted', null, selected: t.categoryId == null),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete transaction', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('For duplicates or wrong rows'),
                onTap: _delete,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _option(String name, int? id, {required bool selected}) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(name),
        trailing: selected ? const Icon(Icons.check, color: teal) : null,
        onTap: () => _pick(id),
      );
}
