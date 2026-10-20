import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/utils/map_math.dart';
import '../../data/models/route_model.dart';
import '../../data/repositories/navigation_repo.dart';

class NavigationState {
  final NavigationRoute? currentRoute;
  final LatLng? currentLocation;
  final double currentHeading;
  final bool isRerouting;
  final RouteStep? currentStep;
  final int stepIndex;

  NavigationState({
    this.currentRoute,
    this.currentLocation,
    this.currentHeading = 0.0,
    this.isRerouting = false,
    this.currentStep,
    this.stepIndex = 0,
  });

  NavigationState copyWith({
    NavigationRoute? currentRoute,
    LatLng? currentLocation,
    double? currentHeading,
    bool? isRerouting,
    RouteStep? currentStep,
    int? stepIndex,
  }) {
    return NavigationState(
      currentRoute: currentRoute ?? this.currentRoute,
      currentLocation: currentLocation ?? this.currentLocation,
      currentHeading: currentHeading ?? this.currentHeading,
      isRerouting: isRerouting ?? this.isRerouting,
      currentStep: currentStep ?? this.currentStep,
      stepIndex: stepIndex ?? this.stepIndex,
    );
  }
}

class NavigationController extends Notifier<NavigationState> {
  StreamSubscription<Position>? _positionSub;
  LatLng? _destination;
  int _deviationCount = 0;

  @override
  NavigationState build() {
    // Cannot start tracking directly in build synchronously if it calls setState immediately, but listen is async.
    // However, it's safer to start tracking after a small delay or explicitly.
    Future.microtask(() => _startTracking());
    
    // Cleanup on dispose
    ref.onDispose(() {
      _positionSub?.cancel();
    });
    
    return NavigationState();
  }

  void setDestination(LatLng dest) async {
    _destination = dest;
    await _fetchInitialRoute();
  }

  Future<void> _fetchInitialRoute() async {
    if (state.currentLocation == null || _destination == null) return;
    state = state.copyWith(isRerouting: true);
    
    final repo = ref.read(navigationRepoProvider);
    final route = await repo.fetchRoute(state.currentLocation!, _destination!);
    state = state.copyWith(
      currentRoute: route,
      isRerouting: false,
      currentStep: route?.steps.isNotEmpty == true ? route!.steps.first : null,
      stepIndex: 0,
    );
  }

  void _startTracking() {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // updates every 2 meters
      ),
    ).listen((pos) {
      final currentLoc = LatLng(pos.latitude, pos.longitude);
      state = state.copyWith(
        currentLocation: currentLoc,
        currentHeading: pos.heading,
      );

      _checkDeviation(currentLoc);
    });
  }

  void _checkDeviation(LatLng currentLoc) {
    if (state.currentRoute == null || _destination == null || state.isRerouting) return;

    final isOnPath = MapMath.isLocationOnPath(currentLoc, state.currentRoute!.overviewPolyline, tolerance: 35.0);
    
    if (!isOnPath) {
      _deviationCount++;
      if (_deviationCount > 3) {
        // Trigger reroute
        _deviationCount = 0;
        _fetchInitialRoute();
      }
    } else {
      _deviationCount = 0;
      _updateCurrentStep(currentLoc);
    }
  }

  void _updateCurrentStep(LatLng currentLoc) {
    if (state.currentRoute == null || state.currentStep == null) return;
    
    final endLoc = state.currentStep!.endLocation;
    final dist = Geolocator.distanceBetween(
      currentLoc.latitude, currentLoc.longitude,
      endLoc.latitude, endLoc.longitude,
    );
    
    if (dist < 30) {
      // We arrived at the end of the step, advance
      int nextIdx = state.stepIndex + 1;
      if (nextIdx < state.currentRoute!.steps.length) {
        state = state.copyWith(
          stepIndex: nextIdx,
          currentStep: state.currentRoute!.steps[nextIdx],
        );
      }
    }
  }

  void stopNavigation() {
    _destination = null;
    state = NavigationState(currentLocation: state.currentLocation); // clear route
  }
}

final navigationRepoProvider = Provider((ref) => NavigationRepository());

final navigationControllerProvider = NotifierProvider<NavigationController, NavigationState>(NavigationController.new);
