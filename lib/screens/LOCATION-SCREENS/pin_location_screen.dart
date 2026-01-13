import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../generated/l10n/app_localizations.dart';

class PinLocationScreen extends StatefulWidget {
  final LatLng? initialLocation;

  const PinLocationScreen({Key? key, this.initialLocation}) : super(key: key);

  @override
  _PinLocationScreenState createState() => _PinLocationScreenState();
}

class _PinLocationScreenState extends State<PinLocationScreen>
    with TickerProviderStateMixin {
  LatLng? _selectedLocation;
  GoogleMapController? _mapController;
  bool _isMapLoading = true;
  bool _isLocationLoading = false;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  // Define the custom jade green color
  final Color jadeGreen = const Color(0xFF00A86B);

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    
    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Start pulse animation for loading
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLocation = position;
    });
    
    // Add a small haptic feedback
    _addHapticFeedback();
  }

  void _addHapticFeedback() {
    // You can add haptic feedback here if needed
    // HapticFeedback.lightImpact();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    
    // Set map style for better appearance (optional)
    _setMapStyle();
    
    // Animate to initial location if provided
    if (widget.initialLocation != null) {
      _animateToLocation(widget.initialLocation!);
    }
    
    // Delay to ensure map is fully rendered
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _isMapLoading = false;
        });
        _fadeController.forward();
        _pulseController.stop();
      }
    });
  }

  void _setMapStyle() async {
    // You can add custom map styling here
    try {
      final String mapStyle = '''
        [
          {
            "featureType": "poi.business",
            "stylers": [{"visibility": "off"}]
          },
          {
            "featureType": "poi.park",
            "elementType": "labels.text",
            "stylers": [{"visibility": "off"}]
          }
        ]
      ''';
      await _mapController?.setMapStyle(mapStyle);
    } catch (e) {
      // Handle styling error gracefully
      debugPrint('Map styling error: $e');
    }
  }

  void _animateToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 16.0,
          tilt: 0,
          bearing: 0,
        ),
      ),
    );
  }

  void _getCurrentLocation() async {
    if (_isLocationLoading) return;
    
    setState(() {
      _isLocationLoading = true;
    });

    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationError('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationError('Location permissions are permanently denied');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final currentLocation = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _selectedLocation = currentLocation;
      });

      _animateToLocation(currentLocation);
      _addHapticFeedback();
      
    } catch (e) {
      _showLocationError('Failed to get current location: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
        });
      }
    }
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: jadeGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: jadeGreen.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).loading ?? 'Loading map...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomMarker() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: jadeGreen,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        color: Colors.white,
        size: 30,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map with improved settings
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation ?? const LatLng(35.1856, 33.3823),
              zoom: widget.initialLocation != null ? 16.0 : 10.0,
            ),
            onTap: _onMapTap,
            markers: _selectedLocation == null
                ? {}
                : {
                    Marker(
                      markerId: const MarkerId('selected-location'),
                      position: _selectedLocation!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueGreen,
                      ),
                    ),
                  },
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // We'll create a custom one
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
            liteModeEnabled: false, // Ensure full map functionality
            mapType: MapType.normal,
            // Improve map quality
            buildingsEnabled: true,
            indoorViewEnabled: false,
            trafficEnabled: false,
          ),

          // Loading overlay
          if (_isMapLoading)
            AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: 1.0 - _fadeAnimation.value,
                  child: _buildLoadingOverlay(),
                );
              },
            ),

          // Custom back button with improved styling
          Positioned(
            top: statusBarHeight + 16,
            left: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Current location button
          Positioned(
            top: statusBarHeight + 80,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _getCurrentLocation,
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _isLocationLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00A86B),
                            ),
                          ),
                        )
                      : Icon(
                          Icons.my_location,
                          color: jadeGreen,
                          size: 24,
                        ),
                ),
              ),
            ),
          ),

          // Enhanced bottom buttons with better spacing and styling
          if (!_isMapLoading)
            Positioned(
              bottom: mediaQuery.padding.bottom + 20,
              left: 20,
              right: 20,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedLocation != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: jadeGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: jadeGreen,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lat: ${_selectedLocation!.latitude.toStringAsFixed(4)}, '
                                  'Lng: ${_selectedLocation!.longitude.toStringAsFixed(4)}',
                                  style: TextStyle(
                                    color: jadeGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          // Cancel Button
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, null),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: Text(
                                loc.cancel,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Done Button
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _selectedLocation != null
                                  ? () => Navigator.pop(context, _selectedLocation)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: jadeGreen,
                                disabledBackgroundColor: Colors.grey.shade300,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                              ),
                              child: Text(
                                loc.done,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}