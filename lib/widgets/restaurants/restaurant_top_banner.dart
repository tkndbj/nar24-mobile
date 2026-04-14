import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../cloudinary_image.dart';

class _BannerItem {
  const _BannerItem({
    required this.imageUrl,
    required this.order,
    this.linkedRestaurantId,
  });

  final String imageUrl;
  final int order;
  final String? linkedRestaurantId;

factory _BannerItem.fromDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return _BannerItem(
      imageUrl: (data['imageStoragePath'] as String?) ??
          (data['imageUrl'] as String? ?? ''),
      order: (data['order'] as int?) ?? 0,
      linkedRestaurantId: data['linkedRestaurantId'] as String?,
    );
  }
}

const _kBannerInterval = Duration(seconds: 5);

class RestaurantTopBanner extends StatefulWidget {
  const RestaurantTopBanner({super.key});

  @override
  State<RestaurantTopBanner> createState() => _RestaurantTopBannerState();
}

class _RestaurantTopBannerState extends State<RestaurantTopBanner> {
  late final PageController _controller;
  int _current = 0;
  Timer? _timer;

  List<_BannerItem> _banners = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _fetchBanners();
  }

  // ── One-time Firestore fetch ──────────────────────────────────────────────

  Future<void> _fetchBanners() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('restaurant_banners')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();

      final items = snap.docs
          .map(_BannerItem.fromDoc)
          .where((b) => b.imageUrl.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _banners = items;
        _loading = false;
      });

      _startTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Auto-scroll timer ─────────────────────────────────────────────────────

  void _startTimer() {
    if (_banners.length <= 1) return;
    _timer = Timer.periodic(_kBannerInterval, (_) {
      if (!mounted || _banners.isEmpty) return;
      final next = (_current + 1) % _banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ── Placeholder / skeleton ────────────────────────────────────────────────

  Widget _placeholder() => Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant, size: 48, color: Colors.orange),
      );

  Widget _skeleton() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 7,
          child: Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.orange,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return _skeleton();
    if (_banners.isEmpty) return _placeholder();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: Stack(
          children: [
            // ── PageView ────────────────────────────────────────────────────
            PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _current = i),
              itemCount: _banners.length,
              itemBuilder: (_, i) {
                final banner = _banners[i];
                final child = _NetworkImage(url: banner.imageUrl);
                if (banner.linkedRestaurantId == null ||
                    banner.linkedRestaurantId!.isEmpty) {
                  return child;
                }
                return GestureDetector(
                  onTap: () => context.push(
                    '/restaurant-detail/${banner.linkedRestaurantId}',
                  ),
                  child: child,
                );
              },
            ),

            // ── Gradient overlay ─────────────────────────────────────────────
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.45),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
              ),
            ),

            // ── Dots ─────────────────────────────────────────────────────────
            if (_banners.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_banners.length, (i) {
                    return GestureDetector(
                      onTap: () => _controller.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _current ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _current
                              ? Colors.white
                              : Colors.white.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Network image with fade-in ────────────────────────────────────────────────

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return CloudinaryImage.banner(
      source: url,
      cdnWidth: 800,
      fit: BoxFit.cover,
      placeholderBuilder: (_) => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.orange,
        ),
      ),
      errorBuilder: (_) => Container(
        color: Colors.orange.withOpacity(0.12),
        alignment: Alignment.center,
        child: const Icon(Icons.restaurant, size: 48, color: Colors.orange),
      ),
    );
  }
}
