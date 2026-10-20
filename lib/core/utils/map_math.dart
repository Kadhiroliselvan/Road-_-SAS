import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mt;
import 'dart:math' as math;

class MapMath {
  /// Check if point is on the path with a given tolerance in meters
  static bool isLocationOnPath(LatLng point, List<LatLng> polyline, {double tolerance = 30.0}) {
    final mtPoint = mt.LatLng(point.latitude, point.longitude);
    final mtPoly = polyline.map((p) => mt.LatLng(p.latitude, p.longitude)).toList();
    return mt.PolygonUtil.isLocationOnPath(mtPoint, mtPoly, false, tolerance: tolerance);
  }

  /// Calculates bearing from start to end in degrees
  static double calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lng1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lng2 = end.longitude * math.pi / 180;

    final dLon = lng2 - lng1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    double brng = math.atan2(y, x);
    brng = brng * 180 / math.pi;
    brng = (brng + 360) % 360;
    return brng;
  }
}
