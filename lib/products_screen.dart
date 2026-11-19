import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'main.dart' show gold, mutedCol, textCol, redAccent;
import 'orders_screen.dart' show bytesFrom;

// Must match the sections on the customer website exactly
const sections = ['Cold Drinks', 'Hot Snacks', 'Lays (Chips)', 'Carbonated Drinks', 'Popcorn', 'Ice Creams'];

String _sortKey(QueryDocumentSnapshot d) {
  final m = d.data() as Map<String, dynamic>;
  final idx = sections.indexOf((m['section'] ?? '').toString());
  return '${(idx + 10).toString().padLeft(3, '0')}${m['name'] ?? ''}';
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: gold,
        foregroundColor: const Color(0xFF2A1606),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductFormScreen()),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.toList()..sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
          if (docs.isEmpty) {
            return const Center(child: Text('No products yet. Tap Add product.', style: TextStyle(color: mutedCol)));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: docs.length,
            itemBuilder: (context, i) => _ProductTile(doc: docs[i]),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _ProductTile({required this.doc});

  Future<void> _delete(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('It will be removed from the customer website.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final name = (d['name'] ?? '').toString();
    final price = d['price'] ?? 0;
    final section = (d['section'] ?? '').toString();
    final stock = d['stock'] is num ? (d['stock'] as num).toInt() : 0;
    final sold = d['sold'] is num ? (d['sold'] as num).toInt() : 0;
    final photo = bytesFrom(d['photo']);
    final soldOut = stock <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                color: Colors.white,
                child: photo != null
                    ? Image.memory(photo, fit: BoxFit.cover)
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: textCol, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(section, style: const TextStyle(color: mutedCol, fontSize: 12)),
                  Text(
                    '₹$price  ·  ${soldOut ? 'Sold Out' : '$stock left'}',
                    style: TextStyle(color: soldOut ? redAccent : gold, fontWeight: FontWeight.w600),
                  ),
                  if (sold > 0) Text('$sold sold', style: const TextStyle(color: mutedCol, fontSize: 12)),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: gold),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProductFormScreen(doc: doc)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: redAccent),
                  onPressed: () => _delete(context, name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Used for both adding a new product and editing an existing one
class ProductFormScreen extends StatefulWidget {
  final QueryDocumentSnapshot? doc;
  const ProductFormScreen({super.key, this.doc});
  @override
  State<ProductFormScreen> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductFormScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();
  String _section = sections.first;
  String? _photo;
  Uint8List? _preview;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.doc != null;

  @override
  void initState() {
    super.initState();
    final d = widget.doc?.data() as Map<String, dynamic>?;
    if (d != null) {
      _name.text = (d['name'] ?? '').toString();
      _price.text = '${d['price'] ?? ''}';
      _stock.text = '${d['stock'] ?? ''}';
      final s = (d['section'] ?? '').toString();
      if (sections.contains(s)) _section = s;
      final p = d['photo'];
      if (p is String && p.isNotEmpty) {
        _photo = p;
        _preview = bytesFrom(p);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _fail(String text) {
    setState(() {
      _error = text;
      _busy = false;
    });
  }

  // Crops the picked photo to a centred square, so there is no white space
  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (x == null) return;
    final raw = await x.readAsBytes();
    var decoded = img.decodeImage(raw);
    if (decoded == null) {
      _fail('Could not read this photo. Please pick another one.');
      return;
    }
    decoded = img.bakeOrientation(decoded);
    final side = min(decoded.width, decoded.height);
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final small = img.copyResize(square, width: 600);
    final bytes = Uint8List.fromList(img.encodeJpg(small, quality: 70));
    final data = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    if (data.length > 250000) {
      _fail('This photo is too large. Please pick a smaller one.');
      return;
    }
    setState(() {
      _photo = data;
      _preview = bytes;
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim());
    final stock = int.tryParse(_stock.text.trim());
    if (name.isEmpty) return _fail('Enter the product name.');
    if (price == null || price < 0) return _fail('Enter the price in whole rupees, e.g. 50.');
    if (stock == null || stock < 0) return _fail('Enter the stock quantity, e.g. 100.');
    if (_photo == null) return _fail('Add a product photo.');

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = {
        'name': name,
        'price': price,
        'section': _section,
        'stock': stock,
        'photo': _photo,
      };
      if (_editing) {
        await widget.doc!.reference.update(data);
      } else {
        await FirebaseFirestore.instance.collection('products').add(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _fail('Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxSize = MediaQuery.of(context).size.width - 32;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit product' : 'Add product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: boxSize,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _preview == null
                  ? const Center(
                      child: Text('Tap to choose a photo (it is cropped square)',
                          style: TextStyle(color: Colors.black54)))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(_preview!, fit: BoxFit.cover),
                    ),
            ),
          ),
          if (_editing)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Tap the photo to change it', style: TextStyle(color: mutedCol, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Product name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _section,
            decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
            items: sections.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => _section = v ?? _section),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Stock quantity (e.g. 100)', border: OutlineInputBorder()),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: redAccent)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving...' : (_editing ? 'Save changes' : 'Save product'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
