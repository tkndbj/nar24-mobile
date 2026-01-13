// File: list_product_kitchen_appliances.dart
import 'package:flutter/material.dart';
import '../../generated/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ListProductKitchenAppliancesScreen extends StatefulWidget {
  // Accept dynamic attributes instead of hard-coded fields
  final Map<String, dynamic>? initialAttributes;

  const ListProductKitchenAppliancesScreen({
    Key? key,
    this.initialAttributes,
  }) : super(key: key);

  @override
  _ListProductKitchenAppliancesScreenState createState() =>
      _ListProductKitchenAppliancesScreenState();
}

class _ListProductKitchenAppliancesScreenState
    extends State<ListProductKitchenAppliancesScreen> {
  // raw appliance keys
  static const List<String> _applianceKeys = [
    'Microwave',
    'CoffeeMachine',
    'Blender',
    'FoodProcessor',
    'Mixer',
    'Toaster',
    'Kettle',
    'RiceCooker',
    'SlowCooker',
    'PressureCooker',
    'AirFryer',
    'Juicer',
    'Grinder',
    'Oven',    
    'IceMaker',
    'WaterDispenser',
    'FoodDehydrator',
    'Steamer',
    'Grill',
    'SandwichMaker',
    'Waffle_Iron',
    'Deep_Fryer',
    'Bread_Maker',
    'Yogurt_Maker',
    'Ice_Cream_Maker',
    'Pasta_Maker',
    'Meat_Grinder',
    'Can_Opener',
    'Knife_Sharpener',
    'Scale',
    'Timer',
  ];
  String? _selectedAppliance;

  @override
  void initState() {
    super.initState();
    // Load from dynamic attributes if provided
    if (widget.initialAttributes != null) {
      _selectedAppliance = widget.initialAttributes!['kitchenAppliance'] as String?;
    }
  }

  String _localizedAppliance(String raw, AppLocalizations l10n) {
    switch (raw) {
      case 'Microwave':
        return l10n.kitchenApplianceMicrowave;
      case 'CoffeeMachine':
        return l10n.kitchenApplianceCoffeeMachine;
      case 'Blender':
        return l10n.kitchenApplianceBlender;
      case 'FoodProcessor':
        return l10n.kitchenApplianceFoodProcessor;
      case 'Mixer':
        return l10n.kitchenApplianceMixer;
      case 'Toaster':
        return l10n.kitchenApplianceToaster;
      case 'Kettle':
        return l10n.kitchenApplianceKettle;
      case 'RiceCooker':
        return l10n.kitchenApplianceRiceCooker;
      case 'SlowCooker':
        return l10n.kitchenApplianceSlowCooker;
      case 'PressureCooker':
        return l10n.kitchenAppliancePressureCooker;
      case 'AirFryer':
        return l10n.kitchenApplianceAirFryer;
      case 'Juicer':
        return l10n.kitchenApplianceJuicer;
      case 'Grinder':
        return l10n.kitchenApplianceGrinder;
      case 'Oven':
        return l10n.kitchenApplianceOven;    
         
      
      case 'IceMaker':
        return l10n.kitchenApplianceIceMaker;
      case 'WaterDispenser':
        return l10n.kitchenApplianceWaterDispenser;
      case 'FoodDehydrator':
        return l10n.kitchenApplianceFoodDehydrator;
      case 'Steamer':
        return l10n.kitchenApplianceSteamer;
      case 'Grill':
        return l10n.kitchenApplianceGrill;
      case 'SandwichMaker':
        return l10n.kitchenApplianceSandwichMaker;
      case 'Waffle_Iron':
        return l10n.kitchenApplianceWaffleIron;
      case 'Deep_Fryer':
        return l10n.kitchenApplianceDeepFryer;
      case 'Bread_Maker':
        return l10n.kitchenApplianceBreadMaker;
      case 'Yogurt_Maker':
        return l10n.kitchenApplianceYogurtMaker;
      case 'Ice_Cream_Maker':
        return l10n.kitchenApplianceIceCreamMaker;
      case 'Pasta_Maker':
        return l10n.kitchenAppliancePastaMaker;
      case 'Meat_Grinder':
        return l10n.kitchenApplianceMeatGrinder;
      case 'Can_Opener':
        return l10n.kitchenApplianceCanOpener;
      case 'Knife_Sharpener':
        return l10n.kitchenApplianceKnifeSharpener;
      case 'Scale':
        return l10n.kitchenApplianceScale;
      case 'Timer':
        return l10n.kitchenApplianceTimer;
      default:
        return raw;
    }
  }

  void _saveKitchenAppliance() {
    if (_selectedAppliance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context).pleaseSelectKitchenAppliance),
        ),
      );
      return;
    }

    // Return the kitchen appliance as dynamic attributes
    final result = <String, dynamic>{
      'kitchenAppliance': _selectedAppliance,
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
          l10n.selectKitchenAppliance,
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
              // Scrollable list of appliances
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          l10n.selectKitchenApplianceType,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ..._applianceKeys.map((appliance) {
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: isDark
                                  ? const Color.fromARGB(255, 45, 43, 60)
                                  : Colors.white,
                              child: RadioListTile<String>(
                                title: Text(
                                  _localizedAppliance(appliance, l10n),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                value: appliance,
                                groupValue: _selectedAppliance,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedAppliance = value;
                                  });
                                },
                                activeColor: const Color(0xFF00A86B),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark 
                                  ? Colors.grey[700] 
                                  : Colors.grey[300],
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
                    onPressed: _saveKitchenAppliance,
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