import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

class SosHelper {
  static final Telephony telephony = Telephony.instance;

  static Future<void> triggerBackgroundSos(BuildContext context, double? latitude, double? longitude) async {
    final prefs = await SharedPreferences.getInstance();
    
    final List<String> phoneNumbers = [];
    final p1 = prefs.getString('contact_phone_1') ?? '';
    final p2 = prefs.getString('contact_phone_2') ?? '';
    final p3 = prefs.getString('contact_phone_3') ?? '';

    if (p1.isNotEmpty) phoneNumbers.add(p1);
    if (p2.isNotEmpty) phoneNumbers.add(p2);
    if (p3.isNotEmpty) phoneNumbers.add(p3);

    if (phoneNumbers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No emergency contacts saved!')),
        );
      }
      return;
    }

    String message = "SOS! I am in danger.";
    if (latitude != null && longitude != null) {
      message += " My current location is: https://maps.google.com/?q=$latitude,$longitude";
    } else {
      message += " (Location unavailable)";
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sending SOS to ${phoneNumbers.length} contacts...'),
          backgroundColor: Colors.red,
        ),
      );
    }

    // Request permission once, then send to all
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted == true) {
      for (String number in phoneNumbers) {
        try {
          await telephony.sendSms(
            to: number,
            message: message,
          );
        } catch (e) {
          debugPrint("Error sending SMS to $number: $e");
        }
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied!')),
        );
      }
    }
  }
}

class SosFloatingButton extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  
  const SosFloatingButton({super.key, this.latitude, this.longitude});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'sos_btn_${key.hashCode}',
      backgroundColor: Colors.red,
      onPressed: () => SosHelper.triggerBackgroundSos(context, latitude, longitude),
      child: const Icon(Icons.sos, color: Colors.white, size: 30),
    );
  }
}
