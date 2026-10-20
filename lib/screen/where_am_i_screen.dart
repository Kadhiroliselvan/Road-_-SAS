import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../screen/offline_map_screen.dart';
import '../services/location_service.dart';
import '../common/sos_helper.dart';
import '../common/accident_detector.dart';
import '../features/navigation/presentation/screens/smart_navigation_screen.dart';

// ─── Data Models ──────────────────────────────────────────────────────────────

enum FacilityCategory {
  hospital,
  ambulance,
  fire,
  police,
  tow,
  fuel,
}

class Facility {
  final String name;
  final double lat;
  final double lng;
  final FacilityCategory category;

  Facility({required this.name, required this.lat, required this.lng, required this.category});

  factory Facility.fromJson(Map<String, dynamic> json, FacilityCategory category) {
    return Facility(
      name: json['name'] as String? ?? 'Unknown',
      lat: (json['lat'] ?? json['latitude'] as num).toDouble(),
      lng: (json['lng'] ?? json['longitude'] as num).toDouble(),
      category: category,
    );
  }
}

class NearbyFacility {
  final Facility facility;
  double distanceM;
  String? status;
  String? phone;
  bool detailsFetched = false;
  bool detailsLoading = false;

  // Route info
  List<LatLng>? routePoints;
  String? routeDuration;
  String? routeDistance;
  List<String>? routeSteps;
  bool routeLoading = false;

  NearbyFacility({required this.facility, required this.distanceM});

  String get distanceLabel {
    if (distanceM < 1000) return '${distanceM.toStringAsFixed(0)} m';
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }
}

// ─── Isolate helper ───────────────────────────────────────────────────────────

List<Facility> _parseFacilities(Map<String, dynamic> args) {
  final jsonStr = args['json'] as String;
  final category = args['category'] as FacilityCategory;
  final parsed = jsonDecode(jsonStr).cast<Map<String, dynamic>>();
  return parsed.map<Facility>((json) => Facility.fromJson(json, category)).toList();
}

// ─── Google Places API key ───────────────────────────────────────────────────
const String _placesApiKey = 'AIzaSyCb5X-sqSmHlaBUnBz_ydWC-1QSxc3ogHY';

// ─── Panel width ──────────────────────────────────────────────────────────────
const double _panelWidth = 280.0;
const double _tabWidth  = 28.0;
const double _tabHeight = 72.0;

// ─── Screen ───────────────────────────────────────────────────────────────────

class WhereAmIScreen extends StatefulWidget {
  const WhereAmIScreen({super.key});

  @override
  State<WhereAmIScreen> createState() => _WhereAmIScreenState();
}

class _WhereAmIScreenState extends State<WhereAmIScreen>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();
  final LocationService _locationService = LocationService();

  StreamSubscription<Position>? _positionStreamSubscription;
  LatLng? _currentPosition;
  bool _hasPermission = false;

  // Offline POI
  bool _isOfflineMode = true;
  Set<Marker> _facilityMarkers = {};
  List<Facility> _allFacilities = [];
  Map<FacilityCategory, BitmapDescriptor> _categoryIcons = {};

  // Nearest panel
  FacilityCategory _selectedCategory = FacilityCategory.hospital;
  List<NearbyFacility> _nearestFacilities = [];
  final Map<String, NearbyFacility> _facilityStates = {};
  int? _expandedIndex;

  // Route & traffic
  Set<Polyline> _routePolylines = {};
  int? _activeRouteIndex; // which facility has the active route
  bool _trafficEnabled = true;

  // Side-panel animation (slides in from the right)
  late AnimationController _panelAnim;
  late Animation<double> _panelOffset; // 0 = closed, 1 = fully open

  bool get _panelOpen => _panelAnim.value > 0.01;

  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(0.0, 0.0),
    zoom: 2.0,
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelOffset = CurvedAnimation(parent: _panelAnim, curve: Curves.easeOut);

    _initCategoryIcons().then((_) => _loadAllFacilities());
    _initializeLocation();
    AccidentDetectorService().startMonitoring(context);
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _panelAnim.dispose();
    AccidentDetectorService().stopMonitoring();
    super.dispose();
  }

  // ── Toggle panel ─────────────────────────────────────────────────────────

  void _togglePanel() {
    if (_panelAnim.isCompleted) {
      _panelAnim.reverse();
    } else {
      _panelAnim.forward();
      // Auto-fetch details for all facilities when opening in online mode
      if (!_isOfflineMode) {
        for (final nf in _nearestFacilities) {
          _fetchOnlineDetails(nf);
        }
      }
    }
  }

  void _selectCategory(FacilityCategory cat) {
    setState(() {
      _selectedCategory = cat;
      _expandedIndex = null;
    });
    _refreshMarkersAndPanel();
    // Auto‑show route for the first nearest facility when online
    if (!_isOfflineMode && _nearestFacilities.isNotEmpty) {
      // Expand first item and fetch its route
      setState(() => _expandedIndex = 0);
      _fetchRoute(0);
    }
    if (_panelOpen && !_isOfflineMode) {
      for (final nf in _nearestFacilities) {
        _fetchOnlineDetails(nf);
      }
    }
  }

  // ── Custom markers ────────────────────────────────────────────────────────

  Future<void> _initCategoryIcons() async {
    final Map<FacilityCategory, Color> catColors = {
      FacilityCategory.hospital: Colors.red,
      FacilityCategory.ambulance: Colors.orange,
      FacilityCategory.fire: Colors.deepOrange,
      FacilityCategory.police: Colors.blue,
      FacilityCategory.tow: Colors.brown,
      FacilityCategory.fuel: Colors.green,
    };

    for (var cat in FacilityCategory.values) {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      const double size = 32.0;

      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2,
        Paint()..color = catColors[cat]!,
      );

      final Paint iconPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      // Draw simple symbols inside the circle based on category
      if (cat == FacilityCategory.hospital || cat == FacilityCategory.ambulance) {
         final Paint cross = Paint()
          ..color = Colors.white
          ..strokeWidth = size / 6.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(size * 0.25, size / 2), const Offset(size * 0.75, size / 2), cross);
        canvas.drawLine(const Offset(size / 2, size * 0.25), const Offset(size / 2, size * 0.75), cross);
      } else {
        canvas.drawCircle(const Offset(size / 2, size / 2), size / 4, iconPaint);
      }

      final ui.Image img =
          await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);

      if (data != null) {
        _categoryIcons[cat] = BitmapDescriptor.fromBytes(data.buffer.asUint8List());
      }
    }
    if (mounted) setState(() {});
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initializeLocation() async {
    final bool hasPermission = await _locationService.handlePermission();
    if (!mounted) return;
    setState(() => _hasPermission = hasPermission);

    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Location permissions are required.')));
      return;
    }

    final Position? pos = await _locationService.getCurrentPosition();
    if (pos != null) {
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      _goToPosition(_currentPosition!);
      if (_allFacilities.isNotEmpty) _refreshMarkersAndPanel();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enable GPS to find your location.')));
    }

    _positionStreamSubscription =
        _locationService.getPositionStream()?.listen((Position position) {
      if (!mounted) return;
      setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
      
      if (_activeRouteIndex == null) {
        _goToPosition(_currentPosition!);
      }
      
      if (_allFacilities.isNotEmpty) _refreshMarkersAndPanel();
    });
  }

  Future<void> _goToPosition(LatLng target) async {
    final GoogleMapController ctrl = await _controller.future;
    await ctrl.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 16.0)));
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadAllFacilities() async {
    try {
      final Map<FacilityCategory, String> files = {
        FacilityCategory.hospital: 'assets/hospitals.json',
        FacilityCategory.ambulance: 'assets/ambulance_simple.json',
        FacilityCategory.fire: 'assets/fire_simple.json',
        FacilityCategory.police: 'assets/police_simple.json',
        FacilityCategory.tow: 'assets/tow_simple.json',
        FacilityCategory.fuel: 'assets/fuel_simple.json',
      };

      List<Facility> loaded = [];
      for (var entry in files.entries) {
        final String jsonStr = await rootBundle.loadString(entry.value);
        final facs = await compute(_parseFacilities, {'json': jsonStr, 'category': entry.key});
        loaded.addAll(facs);
      }

      _allFacilities = loaded;
      _refreshMarkersAndPanel();
    } catch (e) {
      debugPrint('Error loading facilities JSON: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load offline data.')));
      }
    }
  }

  /// Builds markers (<= 10 km) and the nearest-5 list for SELECTED category.
  void _refreshMarkersAndPanel() {
    if (_currentPosition == null) return;

    final Set<Marker> newMarkers = {};
    final List<NearbyFacility> withDist = [];

    for (int i = 0; i < _allFacilities.length; i++) {
      final f = _allFacilities[i];
      if (f.category != _selectedCategory) continue; // Only process selected category

      final double distM = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        f.lat,
        f.lng,
      );

      NearbyFacility nf = _facilityStates[f.name] ?? NearbyFacility(facility: f, distanceM: distM);
      nf.distanceM = distM;
      _facilityStates[f.name] = nf;
      withDist.add(nf);

      // Always add markers, even in online mode
      newMarkers.add(Marker(
        markerId: MarkerId('fac_${f.name}_$i'),
        position: LatLng(f.lat, f.lng),
        infoWindow: InfoWindow(
          title: f.name,
          snippet: _isOfflineMode ? 'Tap for info' : 'Tap for route',
          onTap: () {
            // Find index in current _nearestFacilities to highlight/route
            final idx = _nearestFacilities.indexWhere((item) => item.facility.name == f.name);
            if (idx != -1) {
              _onFacilityTap(idx);
              if (!_panelOpen) _togglePanel();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Selected: ${f.name}'))
              );
            }
          },
        ),
        icon: _categoryIcons[f.category] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    withDist.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final nearest5 = withDist.take(5).toList();

    int? newExpandedIndex;
    int? newActiveRouteIndex;

    if (_expandedIndex != null && _expandedIndex! < _nearestFacilities.length) {
      final expandedName = _nearestFacilities[_expandedIndex!].facility.name;
      newExpandedIndex = nearest5.indexWhere((item) => item.facility.name == expandedName);
      if (newExpandedIndex == -1) newExpandedIndex = null;
    }

    if (_activeRouteIndex != null && _activeRouteIndex! < _nearestFacilities.length) {
      final activeName = _nearestFacilities[_activeRouteIndex!].facility.name;
      newActiveRouteIndex = nearest5.indexWhere((item) => item.facility.name == activeName);
      if (newActiveRouteIndex == -1) newActiveRouteIndex = null;
    }

    if (mounted) {
      setState(() {
        _facilityMarkers = newMarkers;
        _nearestFacilities = nearest5;
        _expandedIndex = newExpandedIndex;
        _activeRouteIndex = newActiveRouteIndex;
      });
    }
  }

  void _toggleOfflineMode(bool value) async {
    setState(() {
      _isOfflineMode = value;
      _expandedIndex = null;
      _activeRouteIndex = null;
      _routePolylines = {};
      
      for (final nf in _facilityStates.values) {
        nf.detailsFetched = false;
        nf.detailsLoading = false;
        nf.status = null;
        nf.phone  = null;
        nf.routePoints = null;
        nf.routeDuration = null;
        nf.routeDistance = null;
        nf.routeSteps = null;
        nf.routeLoading = false;
      }
    });
    if (_allFacilities.isEmpty) {
      await _loadAllFacilities();
    } else {
      _refreshMarkersAndPanel();
    }
    if (!value && _nearestFacilities.isNotEmpty) {
      for (final nf in _nearestFacilities) {
        _fetchOnlineDetails(nf);
      }
    }
  }

  // ── Online details ────────────────────────────────────────────────────────

  String _getGooglePlacesType(FacilityCategory cat) {
    switch (cat) {
      case FacilityCategory.hospital:
      case FacilityCategory.ambulance:
        return 'hospital';
      case FacilityCategory.fire:
        return 'fire_station';
      case FacilityCategory.police:
        return 'police';
      case FacilityCategory.tow:
        return 'car_repair';
      case FacilityCategory.fuel:
        return 'gas_station';
    }
  }

  Future<void> _fetchOnlineDetails(NearbyFacility nf) async {
    if (nf.detailsFetched || nf.detailsLoading) return;
    if (mounted) setState(() => nf.detailsLoading = true);

    try {
      String? placeId;
      final pType = _getGooglePlacesType(nf.facility.category);

      final nearbyRes = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${nf.facility.lat},${nf.facility.lng}'
        '&radius=300'
        '&type=$pType'
        '&key=$_placesApiKey',
      ));
      if (!mounted) return;

      final nearbyResults = jsonDecode(nearbyRes.body)['results'] as List?;
      if (nearbyResults != null && nearbyResults.isNotEmpty) {
        placeId = nearbyResults[0]['place_id'] as String?;
      }

      if (placeId == null) {
        final textRes = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
          '?input=${Uri.encodeComponent(nf.facility.name)}'
          '&inputtype=textquery'
          '&locationbias=point:${nf.facility.lat},${nf.facility.lng}'
          '&fields=place_id'
          '&key=$_placesApiKey',
        ));
        if (!mounted) return;
        final candidates = jsonDecode(textRes.body)['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          placeId = candidates[0]['place_id'] as String?;
        }
      }

      if (placeId == null) {
        if (mounted) setState(() {
          nf.status = 'Not available';
          nf.phone  = 'Not available';
          nf.detailsFetched = true;
          nf.detailsLoading = false;
        });
        return;
      }

      final detailRes = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId'
        '&fields=opening_hours,formatted_phone_number'
        '&key=$_placesApiKey',
      ));
      if (!mounted) return;

      final result  = jsonDecode(detailRes.body)['result'] as Map<String, dynamic>?;
      final openNow = result?['opening_hours']?['open_now'] as bool?;
      final phone   = result?['formatted_phone_number'] as String?;

      if (mounted) setState(() {
        nf.status = openNow == null
            ? 'Unknown'
            : (openNow ? 'OPEN' : 'CLOSED');
        nf.phone  = phone ?? 'Not available';
        nf.detailsFetched = true;
        nf.detailsLoading = false;
      });
    } catch (e) {
      debugPrint('Places fetch error: $e');
      if (mounted) setState(() {
        nf.status = 'Not available';
        nf.phone  = 'Not available';
        nf.detailsFetched = true;
        nf.detailsLoading = false;
      });
    }
  }

  void _onFacilityTap(int index) {
    if (!_isOfflineMode) {
      _fetchOnlineDetails(_nearestFacilities[index]);
      // Always (re)fetch route so traffic-aware route is shown on every tap
      _fetchRoute(index);
      // Always expand the tapped item in online mode
      setState(() => _expandedIndex = index);
    } else {
      setState(() => _expandedIndex = (_expandedIndex == index) ? null : index);
    }
  }

  void _clearRoute() {
    setState(() {
      _routePolylines = {};
      _activeRouteIndex = null;
      for (final nf in _nearestFacilities) {
        nf.routePoints = null;
        nf.routeDuration = null;
        nf.routeDistance = null;
        nf.routeSteps = null;
        nf.routeLoading = false;
      }
    });
  }

  // ── Google Directions: fetch route polyline ──────────────────────────────

  Future<void> _fetchRoute(int index) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waiting for your location...')));
      return;
    }
    final nf = _nearestFacilities[index];
    if (nf.routeLoading) return;

    setState(() {
      nf.routeLoading = true;
      _activeRouteIndex = index;
      _routePolylines = {}; // clear old route
    });

    try {
      debugPrint('Fetching route for: ${nf.facility.name}');
      final origin =
          '${_currentPosition!.latitude},${_currentPosition!.longitude}';
      final dest = '${nf.facility.lat},${nf.facility.lng}';
      final nowEpoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

      // Traffic-aware routing: departure_time=now, traffic_model=best_guess
      // alternatives=true so the API picks the best route among several options
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$origin'
        '&destination=$dest'
        '&mode=driving'
        '&departure_time=$nowEpoch'
        '&traffic_model=best_guess'
        '&alternatives=true'
        '&key=$_placesApiKey',
      );

      debugPrint('Directions URL (traffic-aware): $url');
      final res = await http.get(url);
      if (!mounted) return;
      
      final body = jsonDecode(res.body);
      final status = body['status'] as String?;
      debugPrint('Directions API Status: $status');

      if (status != 'OK') {
        setState(() => nf.routeLoading = false);
        final errorMsg = body['error_message'] ?? status ?? 'Unknown error';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Route Error: $errorMsg')));
        return;
      }

      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        setState(() => nf.routeLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No route found.')));
        }
        return;
      }

      // Pick the route with the shortest traffic duration when alternatives available
      Map<String, dynamic> bestRoute = routes[0] as Map<String, dynamic>;
      int bestSecs = ((routes[0]['legs'][0]['duration_in_traffic'] ??
              routes[0]['legs'][0]['duration'])['value'] as num)
          .toInt();
      for (int r = 1; r < routes.length; r++) {
        final leg0 = (routes[r] as Map)['legs'][0];
        final secs = ((leg0['duration_in_traffic'] ?? leg0['duration'])['value'] as num).toInt();
        if (secs < bestSecs) {
          bestSecs = secs;
          bestRoute = routes[r] as Map<String, dynamic>;
        }
      }

      final leg = bestRoute['legs'][0];
      final durationInTraffic =
          leg['duration_in_traffic']?['text'] as String? ??
          leg['duration']?['text'] as String? ?? '';
      final distText = leg['distance']?['text'] as String? ?? '';
      final encoded = bestRoute['overview_polyline']['points'] as String;
      final points = _decodePolyline(encoded);

      final steps = leg['steps'] as List?;
      final List<String> parsedSteps = [];
      if (steps != null) {
        for (var step in steps) {
          final rawInst = step['html_instructions'] as String? ?? '';
          // Remove HTML tags and multiple spaces
          final cleanInst = rawInst.replaceAll(RegExp(r'<[^>]*>'), ' ');
          final normalizedInst = cleanInst.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (normalizedInst.isNotEmpty) {
            parsedSteps.add(normalizedInst);
          }
        }
      }

      // Colour the route: green = fast, amber = moderate, red = heavy traffic
      final Color routeColor;
      if (bestSecs < 600) {
        routeColor = const Color(0xFF2E7D32); // green
      } else if (bestSecs < 1800) {
        routeColor = const Color(0xFFF57C00); // amber
      } else {
        routeColor = const Color(0xFFC62828); // red
      }

      setState(() {
        nf.routePoints = points;
        nf.routeDuration = durationInTraffic;
        nf.routeDistance = distText;
        nf.routeSteps = parsedSteps;
        nf.routeLoading = false;
        _routePolylines = {
          Polyline(
            polylineId: const PolylineId('active_route'),
            points: points,
            color: routeColor,
            width: 6,
            patterns: [],
            jointType: JointType.round,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
          ),
        };
      });

      // Fit camera to the route bounds
      final ctrl = await _controller.future;
      if (!mounted) return;
      double minLat = _currentPosition!.latitude,
          maxLat = _currentPosition!.latitude;
      double minLng = _currentPosition!.longitude,
          maxLng = _currentPosition!.longitude;
      for (final p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      await ctrl.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.005, minLng - 0.005),
          northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
        ),
        60,
      ));
    } catch (e) {
      debugPrint('Directions error: $e');
      if (mounted) setState(() => nf.routeLoading = false);
    }
  }

  /// Decode Google's encoded polyline format into a list of LatLng.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where Am I'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Offline Map',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OfflineMapScreen()),
            ),
          ),
          Row(children: [
            const Text('Offline POI'),
            Switch(
              value: _isOfflineMode,
              onChanged: _toggleOfflineMode,
              activeColor: Colors.white,
            ),
          ])
        ],
      ),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _initialPosition,
            myLocationEnabled: _hasPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            trafficEnabled: !_isOfflineMode && _trafficEnabled,
            markers: _facilityMarkers,
            polylines: _routePolylines,
            onMapCreated: (GoogleMapController c) {
              _controller.complete(c);
              if (_currentPosition != null) _goToPosition(_currentPosition!);
            },
          ),

          // ── Route info banner ──────────────────────────────────────────────
          if (!_isOfflineMode && _activeRouteIndex != null)
            _buildRouteBanner(),

          // ── No-permission overlay ──────────────────────────────────────────
          if (!_hasPermission)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(20),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off, size: 50, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Location Permission Required',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          'This app needs location access to show you on the map '
                          'and send your position in case of SOS.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _initializeLocation,
                          icon: const Icon(Icons.settings),
                          label: const Text('Grant Permission / Open Settings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Right-side sliding hospital panel ──────────────────────────────
          _buildSidePanel(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SosFloatingButton(
            latitude: _currentPosition?.latitude,
            longitude: _currentPosition?.longitude,
          ),
          const SizedBox(height: 12),
          // Traffic toggle (online only)
          if (!_isOfflineMode)
            FloatingActionButton(
              heroTag: 'trafficToggle',
              mini: true,
              backgroundColor:
                  _trafficEnabled ? Colors.deepPurple : Colors.grey.shade600,
              tooltip: 'Toggle Traffic Layer',
              onPressed: () =>
                  setState(() => _trafficEnabled = !_trafficEnabled),
              child: const Icon(Icons.traffic, color: Colors.white),
            ),
          if (!_isOfflineMode) const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'locateMe',
            onPressed: () {
              if (_currentPosition != null) {
                _goToPosition(_currentPosition!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Location not yet available.')));
              }
            },
            label: const Text('Locate Me'),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // ── Route info banner ─────────────────────────────────────────────────────

  Widget _buildRouteBanner() {
    final nf = _nearestFacilities[_activeRouteIndex!];

    // Determine traffic colour badge from polyline colour
    Color trafficDot = const Color(0xFF2E7D32);
    String trafficLabel = 'Light traffic';
    if (_routePolylines.isNotEmpty) {
      final c = _routePolylines.first.color;
      if (c == const Color(0xFFF57C00)) {
        trafficDot = const Color(0xFFF57C00);
        trafficLabel = 'Moderate traffic';
      } else if (c == const Color(0xFFC62828)) {
        trafficDot = const Color(0xFFC62828);
        trafficLabel = 'Heavy traffic';
      }
    }

    return Positioned(
      bottom: 110,
      left: 12,
      right: 12,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: Colors.deepPurple.shade800,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.directions_car, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: nf.routeLoading
                    ? const Row(children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 8),
                        Text('Analysing traffic & route…',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Live Traffic badge row
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(children: [
                                Icon(Icons.wifi_tethering, size: 10, color: trafficDot),
                                const SizedBox(width: 4),
                                Text(
                                  'LIVE TRAFFIC',
                                  style: TextStyle(
                                    color: trafficDot,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              trafficLabel,
                              style: const TextStyle(color: Colors.white60, fontSize: 10),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            nf.facility.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.access_time,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              nf.routeDuration ?? '',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.straighten,
                                size: 12, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              nf.routeDistance ?? '',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ]),
                        ],
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                tooltip: 'Clear Route',
                onPressed: _clearRoute,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Side Panel ────────────────────────────────────────────────────────────

  Widget _buildSidePanel() {
    return AnimatedBuilder(
      animation: _panelOffset,
      builder: (context, _) {
        final double t = _panelOffset.value; // 0 = closed, 1 = open
        final double panelRight = -_panelWidth * (1 - t);

        return Positioned(
          top: 80, // below AppBar area
          right: panelRight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Category Tabs ────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: FacilityCategory.values.map((cat) {
                  final isSelected = cat == _selectedCategory;
                  IconData icon;
                  Color color;
                  switch (cat) {
                    case FacilityCategory.hospital: icon = Icons.local_hospital; color = Colors.red; break;
                    case FacilityCategory.ambulance: icon = Icons.medical_services; color = Colors.orange; break;
                    case FacilityCategory.fire: icon = Icons.local_fire_department; color = Colors.deepOrange; break;
                    case FacilityCategory.police: icon = Icons.local_police; color = Colors.blue; break;
                    case FacilityCategory.tow: icon = Icons.car_repair; color = Colors.brown; break;
                    case FacilityCategory.fuel: icon = Icons.local_gas_station; color = Colors.green; break;
                  }

                  return GestureDetector(
                    onTap: () {
                      if (_panelOpen && _selectedCategory == cat) {
                        _togglePanel(); // Compress/collapse if clicking the active tab
                      } else {
                        if (!_panelOpen) _togglePanel(); // Expand
                        _selectCategory(cat);
                      }
                    },
                    child: Container(
                      width: 44,
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : color.withOpacity(0.9),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          bottomLeft: Radius.circular(10),
                        ),
                        boxShadow: [
                          if (isSelected)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(-2, 0),
                            ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: isSelected ? color : Colors.white, size: 20),
                          if (isSelected) ...[
                            const SizedBox(height: 2),
                            AnimatedRotation(
                              turns: t * 0.5,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(Icons.chevron_left,
                                  color: color, size: 16),
                            ),
                          ]
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              // ── Panel body ────────────────────────────────────────
              Container(
                width: _panelWidth,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 16,
                      offset: const Offset(-4, 0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_selectedCategory.name.toUpperCase()} (${_nearestFacilities.length})',
                              style: TextStyle(
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isOfflineMode
                                  ? Colors.orange.shade700
                                  : Colors.green.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _isOfflineMode ? 'OFFLINE' : 'ONLINE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // List
                    if (_nearestFacilities.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No locations found.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: _nearestFacilities.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: 12, endIndent: 12),
                          itemBuilder: (context, index) =>
                              _buildFacilityTile(index),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFacilityTile(int index) {
    final nf = _nearestFacilities[index];
    final bool isExpanded = _expandedIndex == index;

    return InkWell(
      onTap: () {
        _onFacilityTap(index);
        // In online mode, immediately show a snackbar hint while route loads
        if (!_isOfflineMode && _nearestFacilities[index].routePoints == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text('Finding best route to ${_nearestFacilities[index].facility.name}…'),
                ],
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.deepPurple.shade700,
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        color: isExpanded
            ? Colors.deepPurple.withOpacity(0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary row
            Row(
              children: [
                // Rank bubble
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nf.facility.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Distance + Route Button + chevron
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Row(
                children: [
                  Icon(Icons.directions_walk,
                      size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 3),
                  Text(
                    nf.distanceLabel,
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  // Quick-access Route Button
                  if (!_isOfflineMode)
                    GestureDetector(
                      onTap: () {
                        if (_expandedIndex != index) {
                          setState(() => _expandedIndex = index);
                        }
                        _fetchRoute(index);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.directions,
                            size: 18, color: Colors.deepPurple),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),

            // Expanded details
            if (isExpanded) ...[
              const SizedBox(height: 8),
              if (_isOfflineMode) ...[
                _detailRow(Icons.access_time, 'Info unavailable', Colors.grey),
                const SizedBox(height: 4),
                _detailRow(Icons.phone, 'Info unavailable', Colors.grey),
              ]
              else if (nf.detailsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Fetching…',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                )
              else ...[
                _detailRow(
                  Icons.access_time,
                  nf.status ?? 'UNKNOWN',
                  nf.status == 'OPEN'
                      ? Colors.green
                      : nf.status == 'CLOSED'
                          ? Colors.red
                          : Colors.grey,
                ),
                const SizedBox(height: 4),
                _detailRow(Icons.phone, nf.phone ?? 'N/A', Colors.deepPurple),
                const SizedBox(height: 6),
                // ── Route info row ──────────────────────────────────
                if (nf.routeLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.deepPurple),
                      ),
                      SizedBox(width: 8),
                      Text('Getting route…',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  )
                else if (nf.routeDuration != null) ...[
                  _detailRow(
                    Icons.directions_car,
                    '${nf.routeDuration} · ${nf.routeDistance}',
                    Colors.deepPurple,
                  ),
                  const SizedBox(height: 4),
                  if (nf.routeSteps != null && nf.routeSteps!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      height: 140, // Scrollable constrained height for steps
                      child: Scrollbar(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: nf.routeSteps!.length,
                          itemBuilder: (context, idx) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${idx + 1}.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      nf.routeSteps![idx],
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SmartNavigationScreen(
                            destination: LatLng(nf.facility.lat, nf.facility.lng),
                            destinationName: nf.facility.name,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 4, top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Start Navigation',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
