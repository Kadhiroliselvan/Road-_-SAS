import 'dart:io';

import 'package:flutter/material.dart';
import 'package:real_time_car_tracking/common/globs.dart';
import 'package:real_time_car_tracking/common/location_manager.dart';
import 'package:real_time_car_tracking/common/my_http_overrides.dart';
import 'package:real_time_car_tracking/common/service_call.dart';
import 'package:real_time_car_tracking/common/socket_manager.dart';
import 'package:real_time_car_tracking/screen/map_screen.dart';
import 'package:real_time_car_tracking/screen/where_am_i_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:real_time_car_tracking/screen/emergency_contacts_screen.dart';

SharedPreferences? prefs;

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();

  prefs = await SharedPreferences.getInstance();

  ServiceCall.userUUID = Globs.udValueString("uuid");

  if (ServiceCall.userUUID == "") {
    ServiceCall.userUUID = const Uuid().v6();
    Globs.udStringSet(ServiceCall.userUUID, "uuid");
  }

  SocketManager.shared.initSocket();
  LocationManager.shared.initLocation();
  
  bool contactsSaved = prefs?.getBool('contacts_saved') ?? false;
  runApp(ProviderScope(child: MyApp(contactsSaved: contactsSaved)));
}

class MyApp extends StatelessWidget {
  final bool contactsSaved;
  const MyApp({super.key, required this.contactsSaved});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: contactsSaved ? const WhereAmIScreen() : const EmergencyContactsScreen(),
    );
  }
}
