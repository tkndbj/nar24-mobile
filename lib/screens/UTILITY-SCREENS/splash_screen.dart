// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Remove backgroundColor if you want the image to fill every pixel
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/adaexpresssplash.png', // Use your GIF image here
          fit: BoxFit.cover, // Ensures the image fills the screen
        ),
      ),
    );
  }
}
