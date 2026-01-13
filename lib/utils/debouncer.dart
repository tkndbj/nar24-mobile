import 'dart:async';
import 'package:flutter/foundation.dart';

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  // Optional: Add dispose method for consistency
  void dispose() {
    cancel();
  }
}