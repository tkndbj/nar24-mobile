// File: list_product_computer_components.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductComputerComponentsScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductComputerComponentsScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductComputerComponentsScreenState createState() =>
      _ListProductComputerComponentsScreenState();
}

class _ListProductComputerComponentsScreenState
    extends State<ListProductComputerComponentsScreen> {
  // raw component keys
  static const List<String> _componentKeys = [
    'CPU',
    'GPU',
    'RAM',
    'Motherboard',
    'SSD',
    'HDD',
    'PowerSupply',
    'CoolingSystem',
    'Case',
    'OpticalDrive',
    'NetworkCard',
    'SoundCard',
    'Webcam',
  ];
  String? _selectedComponent;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedComponent =
          widget.initialAttributes!['computerComponent'] as String?;
    }
  }

  String _localizedComponent(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'CPU':
        return l10n.computerComponentCPU;
      case 'GPU':
        return l10n.computerComponentGPU;
      case 'RAM':
        return l10n.computerComponentRAM;
      case 'Motherboard':
        return l10n.computerComponentMotherboard;
      case 'SSD':
        return l10n.computerComponentSSD;
      case 'HDD':
        return l10n.computerComponentHDD;
      case 'PowerSupply':
        return l10n.computerComponentPowerSupply;
      case 'CoolingSystem':
        return l10n.computerComponentCoolingSystem;
      case 'Case':
        return l10n.computerComponentCase;
      case 'OpticalDrive':
        return l10n.computerComponentOpticalDrive;
      case 'NetworkCard':
        return l10n.computerComponentNetworkCard;
      case 'SoundCard':
        return l10n.computerComponentSoundCard;
      case 'Webcam':
        return l10n.computerComponentWebcam;
      case 'Headset':
        return l10n.computerComponentHeadset;
      default:
        return raw;
    }
  }

  void _saveComputerComponent() {
    if (_selectedComponent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).pleaseSelectComputerComponent),
        ),
      );
      return;
    }

    // Return the computer component as dynamic attributes
    final result = <String, dynamic>{
      'computerComponent': _selectedComponent,
    };

    // Include any existing attributes that were passed in
    if (widget.initialAttributes != null) {
      widget.initialAttributes!.forEach((key, value) {
        if (!result.containsKey(key)) {
          result[key] = value;
        }
      });
    }

    context.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.selectComputerComponent,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Container(
          color: isDark
              ? const Color.fromARGB(255, 33, 31, 49)
              : const Color(0xFFF5F5F5),
          child: Column(
            children: [
              // Scrollable list of components
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.selectComputerComponentType,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ..._componentKeys.map((component) {
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: isDark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: RadioListTile<String>(
                                title: Text(
                                  _localizedComponent(component, l10n),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                value: component,
                                groupValue: _selectedComponent,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedComponent = value;
                                  });
                                },
                                activeColor: const Color(0xFF00A86B),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color:
                                  isDark ? Colors.grey[700] : Colors.grey[300],
                            ),
                          ],
                        );
                      }).toList(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Pinned Save button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveComputerComponent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 16.0,
                      ),
                    ),
                    child: Text(
                      l10n.save,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
