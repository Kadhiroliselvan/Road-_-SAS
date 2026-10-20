import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'sos_helper.dart';

class AccidentDetectorService {
  static final AccidentDetectorService _instance = AccidentDetectorService._internal();
  factory AccidentDetectorService() => _instance;
  AccidentDetectorService._internal();

  StreamSubscription? _accelerometerSub;
  bool _isMonitoring = false;
  bool _isDialogShowing = false;

  final double _crashThreshold = 45.0; // m/s^2 (Approx 4.5 Gs)

  void startMonitoring(BuildContext context) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _accelerometerSub = userAccelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((event) {
      if (_isDialogShowing) return;

      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      
      if (magnitude > _crashThreshold) {
        _triggerAccidentFlow(context);
      }
    });
  }

  void stopMonitoring() {
    _accelerometerSub?.cancel();
    _isMonitoring = false;
  }

  void _triggerAccidentFlow(BuildContext context) async {
    _isDialogShowing = true;
    _accelerometerSub?.pause(); // Pause sensing while dialog is up

    // Fetch current location quickly
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 5));
    } catch (e) {
      // Ignore
    }

    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AccidentCountdownDialog(
          latitude: pos?.latitude,
          longitude: pos?.longitude,
        ),
      );
    }

    // Resume monitoring after 10 seconds to prevent immediate re-trigger
    await Future.delayed(const Duration(seconds: 10));
    _isDialogShowing = false;
    _accelerometerSub?.resume();
  }
}

class AccidentCountdownDialog extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  const AccidentCountdownDialog({Key? key, this.latitude, this.longitude}) : super(key: key);

  @override
  State<AccidentCountdownDialog> createState() => _AccidentCountdownDialogState();
}

class _AccidentCountdownDialogState extends State<AccidentCountdownDialog> with SingleTickerProviderStateMixin {
  int _countdown = 10;
  Timer? _timer;
  late AnimationController _flashController;
  late Animation<Color?> _flashAnimation;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _setupAudio();
    _setupAnimation();
    _startCountdown();
  }

  void _setupAudio() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    _speakCurrentCount();
  }

  void _speakCurrentCount() async {
    if (_countdown == 10) {
      await _flutterTts.speak("Accident detected! Sending S O S in 10 seconds.");
    } else if (_countdown > 0 && _countdown <= 5) {
      await _flutterTts.speak(_countdown.toString());
    }
  }

  void _setupAnimation() {
    _flashController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..repeat(reverse: true);
    _flashAnimation = ColorTween(begin: Colors.red.shade900, end: Colors.black).animate(_flashController);
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
        _speakCurrentCount();
      } else {
        _timer?.cancel();
        _triggerSosAndClose();
      }
    });
  }

  void _triggerSosAndClose() {
    _flutterTts.speak("Sending S O S now.");
    SosHelper.triggerBackgroundSos(context, widget.latitude, widget.longitude);
    if (mounted) Navigator.of(context).pop(false);
  }

  void _cancelSos() {
    _flutterTts.stop();
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flashAnimation,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: _flashAnimation.value,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 100),
                    const SizedBox(height: 24),
                    const Text(
                      'ACCIDENT DETECTED!',
                      style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'High impact collision detected.\nAutomatically sending SOS to emergency contacts in:',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Text(
                        '$_countdown',
                        style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 60),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _cancelSos,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade900,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('I AM OKAY (CANCEL)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
