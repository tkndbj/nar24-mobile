import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ViewLocationScreen extends StatelessWidget {
  final LatLng location;

  const ViewLocationScreen({Key? key, required this.location}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: location,
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('property_location'),
                position: location,
              ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
          Positioned(
            top: 40,
            left: 10,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () {
                  Navigator.pop(context);
                },
                iconSize: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
