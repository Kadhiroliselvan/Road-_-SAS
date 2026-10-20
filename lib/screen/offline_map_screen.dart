import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../common/sos_helper.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

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

class _NearbyFacility {
  final Facility facility;
  final double distanceM;

  _NearbyFacility({required this.facility, required this.distanceM});

  String get distanceLabel {
    if (distanceM < 1000) return '${distanceM.toStringAsFixed(0)} m';
    return '${(distanceM / 1000).toStringAsFixed(1)} km';
  }
}

List<Facility> _parseFacilities(Map<String, dynamic> args) {
  final jsonStr = args['json'] as String;
  final category = args['category'] as FacilityCategory;
  final parsed = jsonDecode(jsonStr).cast<Map<String, dynamic>>();
  return parsed.map<Facility>((json) => Facility.fromJson(json, category)).toList();
}

// ─── Panel constants ──────────────────────────────────────────────────────────
const double _panelWidth = 280.0;
const double _tabWidth   = 44.0;
const double _tabHeight  = 60.0;

// ─── Screen ───────────────────────────────────────────────────────────────────

class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({super.key});

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen>
    with SingleTickerProviderStateMixin {
  // Map
  VectorTileProvider? _tileProvider;
  vtr.Theme? _theme;
  List<Marker> _markers = [];
  List<Facility> _allFacilities = [];
  bool _isLoading = true;
  String? _errorMessage;
  final MapController _mapController = MapController();

  // Location
  final LocationService _locationService = LocationService();
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Nearest-panel state
  FacilityCategory _selectedCategory = FacilityCategory.hospital;
  List<_NearbyFacility> _nearestFacilities = [];
  int? _expandedIndex;

  // Panel slide animation
  late AnimationController _panelAnim;
  late Animation<double> _panelOffset;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _panelAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelOffset =
        CurvedAnimation(parent: _panelAnim, curve: Curves.easeOut);

    _initOfflineMap();
    _initLocation();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _panelAnim.dispose();
    super.dispose();
  }

  // ── Panel toggle ────────────────────────────────────────────────────────────

  void _togglePanel() {
    if (_panelAnim.isCompleted) {
      _panelAnim.reverse();
    } else {
      _panelAnim.forward();
    }
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    bool hasPermission = await _locationService.handlePermission();
    if (!hasPermission) return;

    Position? pos = await _locationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
      _rebuildMarkersAndPanel();
    }

    _positionStreamSubscription =
        _locationService.getPositionStream()?.listen((Position position) {
      if (!mounted) return;
      setState(() => _currentPosition = LatLng(position.latitude, position.longitude));
      _rebuildMarkersAndPanel();
    });
  }

  // ── Markers + panel list (<= 10 km) ─────────────────────────────────────────

  void _selectCategory(FacilityCategory cat) {
    setState(() {
      _selectedCategory = cat;
      _expandedIndex = null;
    });
    _rebuildMarkersAndPanel();
  }

  void _rebuildMarkersAndPanel() {
    if (_currentPosition == null || _allFacilities.isEmpty) return;

    final newMarkers = <Marker>[];
    final List<_NearbyFacility> withDist = [];

    final Map<FacilityCategory, Color> catColors = {
      FacilityCategory.hospital: Colors.red,
      FacilityCategory.ambulance: Colors.orange,
      FacilityCategory.fire: Colors.deepOrange,
      FacilityCategory.police: Colors.blue,
      FacilityCategory.tow: Colors.brown,
      FacilityCategory.fuel: Colors.green,
    };

    for (final f in _allFacilities) {
      if (f.category != _selectedCategory) continue;

      final double distM = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        f.lat,
        f.lng,
      );

      withDist.add(_NearbyFacility(facility: f, distanceM: distM));

      newMarkers.add(Marker(
        point: LatLng(f.lat, f.lng),
        width: 16,
        height: 16,
        child: GestureDetector(
          onTap: () {
            final km = (distM / 1000).toStringAsFixed(1);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${f.name} · $km km away')),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: catColors[f.category] ?? Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 10),
          ),
        ),
      ));
    }

    withDist.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final nearest5 = withDist.take(5).toList();

    if (mounted) {
      setState(() {
        _markers = newMarkers;
        _nearestFacilities = nearest5;
        _expandedIndex = null;
      });
    }
  }

  // ── Offline map init ────────────────────────────────────────────────────────

  Future<void> _initOfflineMap() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      final String path =
          p.join(dir.path, 'osm-2020-02-10-v3.11_india_chennai.mbtiles');

      if (!File(path).existsSync()) {
        try {
          ByteData data = await rootBundle
              .load('assets/osm-2020-02-10-v3.11_india_chennai.mbtiles');
          List<int> bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          await File(path).writeAsBytes(bytes, flush: true);
        } catch (e) {
          if (mounted) {
            setState(() {
              _errorMessage =
                  'MBTiles file not found in assets. Please place it there.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      final mbtiles = MbTiles(mbtilesPath: path);
      final provider = MbTilesVectorTileProvider(mbtiles: mbtiles);

      final styleString = await rootBundle.loadString('assets/style.json');
      final styleMap = jsonDecode(styleString) as Map<String, dynamic>;
      final theme = vtr.ThemeReader().read(styleMap);

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

      if (mounted) {
        setState(() {
          _tileProvider = provider;
          _theme = theme;
          _allFacilities = loaded;
          _isLoading = false;
        });
        _rebuildMarkersAndPanel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing offline vector map: $e';
          _isLoading = false;
        });
      }
    }
  }

  // ── Tile tap handler ────────────────────────────────────────────────────────

  void _onFacilityTap(int index) {
    setState(() =>
        _expandedIndex = (_expandedIndex == index) ? null : index);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Vector Map')),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_errorMessage!, textAlign: TextAlign.center),
                      ),
                    )
                  : FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(
                        initialCenter: LatLng(13.0827, 80.2707),
                        initialZoom: 12.0,
                        minZoom: 4.0,
                        maxZoom: 14.0,
                      ),
                      children: [
                        VectorTileLayer(
                          theme: _theme!,
                          backgroundTheme: _theme!,
                          tileProviders: TileProviders({
                            'openmaptiles': _tileProvider!,
                          }),
                        ),
                        MarkerLayer(markers: _markers),
                        if (_currentPosition != null)
                          MarkerLayer(markers: [
                            Marker(
                              point: _currentPosition!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.my_location,
                                  color: Colors.blue, size: 30),
                            ),
                          ]),
                      ],
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
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'locate_me_offline',
            onPressed: () {
              if (_currentPosition != null) {
                _mapController.move(_currentPosition!, 15.0);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location not yet available.')),
                );
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // ── Side Panel ──────────────────────────────────────────────────────────────

  Widget _buildSidePanel() {
    return AnimatedBuilder(
      animation: _panelOffset,
      builder: (context, _) {
        final double t = _panelOffset.value;
        final double panelRight = -_panelWidth * (1 - t);

        return Positioned(
          top: 80,
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
                      if (_panelAnim.isCompleted && _selectedCategory == cat) {
                        _togglePanel(); // Compress/collapse if clicking active tab
                      } else {
                        if (!_panelAnim.isCompleted) _togglePanel(); // Expand
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

              // Panel body
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
                      offset: const Offset(0, 4),
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
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OFFLINE',
                              style: TextStyle(
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
      onTap: () => _onFacilityTap(index),
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
            // Name row
            Row(
              children: [
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

            // Distance + chevron
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

            // Expanded details — always "Info unavailable" in offline mode
            if (isExpanded) ...[
              const SizedBox(height: 8),
              _detailRow(Icons.access_time, 'Info unavailable', Colors.grey),
              const SizedBox(height: 4),
              _detailRow(Icons.phone, 'Info unavailable', Colors.grey),
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
