// // lib/services/audio_recorder_service.dart
// import 'package:flutter_sound/flutter_sound.dart';
// import 'dart:io';
// import 'package:permission_handler/permission_handler.dart';

// class AudioRecorderService {
//   final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
//   bool _isInitialized = false;

//   Future<void> init() async {
//     final status = await Permission.microphone.request();
//     if (status != PermissionStatus.granted) {
//       throw Exception("Microphone permission not granted");
//     }
//     await _recorder.openRecorder();
//     _isInitialized = true;
//   }

//   Future<void> startRecording(String filePath) async {
//     if (!_isInitialized) {
//       await init();
//     }
//     await _recorder.startRecorder(
//       toFile: filePath,
//       codec: Codec.pcm16WAV,
//       sampleRate: 16000, // Ensure sampleRate for compatibility
//       numChannels: 1, // Single channel often works best
//     );
//   }

//   Future<String?> stopRecording() async {
//     return await _recorder.stopRecorder();
//   }

//   Future<void> dispose() async {
//     await _recorder.closeRecorder();
//   }
// }
