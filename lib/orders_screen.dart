import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'main.dart' show gold, mutedCol, textCol;

Uint8List? bytesFrom(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  final comma = value.indexOf(',');
  final b64 = comma >= 0 ? value.substring(comma + 1) : value;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

void showFullImage(BuildContext context, String title, Uint8List bytes) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textCol)),
          ),
          Flexible(child: InteractiveViewer(child: Image.memory(bytes))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    ),
  );
}

DateTime _timeOf(Map<String, dynamic> d) {
  final t = d['time'];
  return t is Timestamp ? t.toDate() : DateTime.now();
}

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New orders')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').snapshots(),
        builder: (context, prodSnap) {
          final photos = <String, Uint8List?>{};
          for (final p in prodSnap.data?.docs ?? const <QueryDocumentSnapshot>[]) {
            photos[p.id] = bytesFrom((p.data() as Map<String, dynamic>)['photo']);
          }
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('status', isEqualTo: 'Pending')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error: ${snap.error}', textAlign: TextAlign.center),
                ));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.toList()
                ..sort((a, b) => _timeOf(b.data() as Map<String, dynamic>)
                    .compareTo(_timeOf(a.data() as Map<String, dynamic>)));
              if (docs.isEmpty) {
                return const Center(child: Text('No pending orders', style: TextStyle(color: mutedCol, fontSize: 16)));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) => _OrderCard(doc: docs[i], photos: photos),
              );
            },
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Map<String, Uint8List?> photos;
  const _OrderCard({required this.doc, required this.photos});

  Widget _itemRow(Map<String, dynamic> it) {
    final photo = photos[it['id']];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 56,
              height: 56,
              color: Colors.white,
              child: photo != null
                  ? Image.memory(photo, fit: BoxFit.cover)
                  : const Icon(Icons.fastfood, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(it['name'].toString(),
                style: const TextStyle(color: textCol, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Text('x${it['qty']}', style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = doc.data() as Map<String, dynamic>;
    final seat = (d['seat'] ?? '').toString();
    final pickup = (d['pickupNo'] ?? '').toString();
    final who = (d['name'] ?? '').toString();
    final how = (d['delivery'] ?? '').toString();
    final movie = (d['movie'] ?? '').toString();
    final total = d['total'] ?? 0;
    final items = (d['items'] as List?) ?? [];
    final pay = bytesFrom(d['paymentPhoto']);
    final t = _timeOf(d);
    final timeText = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(12)),
                  child: Text('Seat $seat',
                      style: const TextStyle(color: Color(0xFF2A1606), fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(timeText, style: const TextStyle(color: mutedCol)),
              ],
            ),
            const SizedBox(height: 8),
            Text(pickup, style: const TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold)),
            if (who.isNotEmpty) Text('Name: $who', style: const TextStyle(color: textCol, fontSize: 15)),
            if (how.isNotEmpty) Text('Delivery: $how', style: const TextStyle(color: textCol, fontSize: 15)),
            if (movie.isNotEmpty) Text('Movie: $movie', style: const TextStyle(color: mutedCol, fontSize: 13)),
            const SizedBox(height: 12),
            for (final raw in items) _itemRow(raw as Map<String, dynamic>),
            const Divider(color: Colors.white24),
            Text('Total: ₹$total', style: const TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
            if (pay != null) ...[
              const SizedBox(height: 10),
              const Text('Payment screenshot (tap to view)', style: TextStyle(color: mutedCol, fontSize: 12)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => showFullImage(context, 'Payment screenshot', pay),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(pay, height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await doc.reference.update({'status': 'Delivered'});
                },
                child: const Text('Mark delivered'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
