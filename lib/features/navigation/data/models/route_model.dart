import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final String htmlInstructions;
  final String distanceText;
  final int distanceValue;
  final String durationText;
  final int durationValue;
  final String maneuver;
  final List<LatLng> polyline;

  RouteStep({
    required this.startLocation,
    required this.endLocation,
    required this.htmlInstructions,
    required this.distanceText,
    required this.distanceValue,
    required this.durationText,
    required this.durationValue,
    required this.maneuver,
    required this.polyline,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      startLocation: LatLng(json['start_location']['lat'], json['start_location']['lng']),
      endLocation: LatLng(json['end_location']['lat'], json['end_location']['lng']),
      htmlInstructions: json['html_instructions'] ?? '',
      distanceText: json['distance']?['text'] ?? '',
      distanceValue: json['distance']?['value'] ?? 0,
      durationText: json['duration']?['text'] ?? '',
      durationValue: json['duration']?['value'] ?? 0,
      maneuver: json['maneuver'] ?? '',
      polyline: _decodePolyline(json['polyline']?['points'] ?? ''),
    );
  }

  String get cleanInstructions {
    final cleanInst = htmlInstructions.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return cleanInst.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class NavigationRoute {
  final List<LatLng> overviewPolyline;
  final List<RouteStep> steps;
  final String totalDistanceText;
  final int totalDistanceValue;
  final String durationInTrafficText;
  final int durationInTrafficValue;
  final LatLng startLocation;
  final LatLng endLocation;

  NavigationRoute({
    required this.overviewPolyline,
    required this.steps,
    required this.totalDistanceText,
    required this.totalDistanceValue,
    required this.durationInTrafficText,
    required this.durationInTrafficValue,
    required this.startLocation,
    required this.endLocation,
  });

  factory NavigationRoute.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No routes found');
    }

    // Pick best route based on traffic
    Map<String, dynamic> bestRoute = routes[0];
    int bestSecs = ((routes[0]['legs'][0]['duration_in_traffic'] ?? routes[0]['legs'][0]['duration'])['value'] as num).toInt();
    
    for (int r = 1; r < routes.length; r++) {
      final leg = routes[r]['legs'][0];
      final secs = ((leg['duration_in_traffic'] ?? leg['duration'])['value'] as num).toInt();
      if (secs < bestSecs) {
        bestSecs = secs;
        bestRoute = routes[r];
      }
    }

    final leg = bestRoute['legs'][0];
    final stepsJson = leg['steps'] as List? ?? [];
    
    return NavigationRoute(
      overviewPolyline: _decodePolyline(bestRoute['overview_polyline']['points'] ?? ''),
      steps: stepsJson.map((s) => RouteStep.fromJson(s)).toList(),
      totalDistanceText: leg['distance']?['text'] ?? '',
      totalDistanceValue: leg['distance']?['value'] ?? 0,
      durationInTrafficText: leg['duration_in_traffic']?['text'] ?? leg['duration']?['text'] ?? '',
      durationInTrafficValue: bestSecs,
      startLocation: LatLng(leg['start_location']['lat'], leg['start_location']['lng']),
      endLocation: LatLng(leg['end_location']['lat'], leg['end_location']['lng']),
    );
  }
}

List<LatLng> _decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    final dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    lat += dlat;

    shift = 0; result = 0;
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
