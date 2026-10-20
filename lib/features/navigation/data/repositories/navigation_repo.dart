import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/constants/api_keys.dart';
import '../models/route_model.dart';

class NavigationRepository {
  Future<NavigationRoute?> fetchRoute(LatLng origin, LatLng destination) async {
    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${destination.latitude},${destination.longitude}';
    final nowEpoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$originStr'
      '&destination=$destStr'
      '&mode=driving'
      '&departure_time=$nowEpoch'
      '&traffic_model=best_guess'
      '&alternatives=true'
      '&key=${ApiKeys.googlePlacesApiKey}',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'OK') {
          return NavigationRoute.fromJson(body);
        }
      }
    } catch (e) {
      print('Error fetching route: $e');
    }
    return null;
  }
}
