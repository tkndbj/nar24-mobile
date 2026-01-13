import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class PersonalDataScreen extends StatefulWidget {
  final String? agreementAssetPath;
  final String? customTitle;
  final String? customText;

  const PersonalDataScreen({
    Key? key,
    this.agreementAssetPath = 'assets/agreements/kisisel_veriler.txt',
    this.customTitle,
    this.customText,
  }) : super(key: key);

  @override
  State<PersonalDataScreen> createState() => _PersonalDataScreenState();
}

class _PersonalDataScreenState extends State<PersonalDataScreen> {
  String agreementTitle = '';
  String agreementText = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAgreement();
  }

  Future<void> _loadAgreement() async {
    try {
      if (widget.customTitle != null && widget.customText != null) {
        // Use custom text if provided
        agreementTitle = widget.customTitle!;
        agreementText = widget.customText!;
      } else {
        // Load from asset file
        final content = await rootBundle.loadString(widget.agreementAssetPath!);
        final lines = content.split('\n');

        // First non-empty line is the title
        agreementTitle = lines.firstWhere((line) => line.trim().isNotEmpty,
            orElse: () => 'Agreement');

        // Rest is the content (skip the title line)
        final titleIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
        agreementText = lines.skip(titleIndex + 1).join('\n').trim();
      }
    } catch (e) {
      // Fallback in case of error
      agreementTitle = 'Agreement';
      agreementText = 'Error loading agreement content. Please try again.';
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDarkMode ? const Color(0xFF1C1A29) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      agreementTitle,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    Text(
                      agreementText,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: isDarkMode ? Colors.white : Colors.black,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
