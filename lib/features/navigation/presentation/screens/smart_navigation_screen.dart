import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:real_time_car_tracking/features/navigation/presentation/controllers/navigation_controller.dart';
import 'package:real_time_car_tracking/features/navigation/presentation/widgets/bottom_eta_sheet.dart';

class SmartNavigationScreen extends ConsumerStatefulWidget {
  final LatLng destination;
  final String destinationName;

  const SmartNavigationScreen({
    Key? key,
    required this.destination,
    required this.destinationName,
  }) : super(key: key);

  @override
  ConsumerState<SmartNavigationScreen> createState() => _SmartNavigationScreenState();
}

class _SmartNavigationScreenState extends ConsumerState<SmartNavigationScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  bool _trafficEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(navigationControllerProvider.notifier).setDestination(widget.destination);
    });
  }

  @override
  void deactivate() {
    ref.read(navigationControllerProvider.notifier).stopNavigation();
    super.deactivate();
  }

  void _onMapCreated(GoogleMapController controller) async {
    _controller.complete(controller);
    // Dark theme can be applied here
  }

  void _recenterCamera(LatLng location, double heading) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: location,
        zoom: 18.0,
        tilt: 45.0,
        bearing: heading,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final navState = ref.watch(navigationControllerProvider);

    if (navState.currentLocation != null) {
      _recenterCamera(navState.currentLocation!, navState.currentHeading);
    }

    Set<Polyline> polylines = {};
    if (navState.currentRoute != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route_path'),
          points: navState.currentRoute!.overviewPolyline,
          color: Colors.cyanAccent.shade400,
          width: 8,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        infoWindow: InfoWindow(title: widget.destinationName),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };

    if (navState.currentLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: navState.currentLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: navState.currentHeading,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: navState.currentLocation ?? widget.destination,
              zoom: 15.0,
            ),
            polylines: polylines,
            markers: markers,
            trafficEnabled: _trafficEnabled,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
          ),
          
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingMapControls(
              onRecenter: () {
                if (navState.currentLocation != null) {
                  _recenterCamera(navState.currentLocation!, navState.currentHeading);
                }
              },
              onToggleTraffic: () {
                setState(() => _trafficEnabled = !_trafficEnabled);
              },
              isTrafficEnabled: _trafficEnabled,
            ),
          ),

          if (navState.currentStep != null || navState.isRerouting)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: TurnByTurnBanner(
                step: navState.currentStep,
                isRerouting: navState.isRerouting,
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BottomEtaSheet(
              route: navState.currentRoute,
              isRerouting: navState.isRerouting,
              onEndNavigation: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
