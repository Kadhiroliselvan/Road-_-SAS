import 'package:flutter/material.dart';
import '../../data/models/route_model.dart';

class BottomEtaSheet extends StatelessWidget {
  final NavigationRoute? route;
  final bool isRerouting;
  final VoidCallback onEndNavigation;

  const BottomEtaSheet({
    Key? key,
    required this.route,
    required this.isRerouting,
    required this.onEndNavigation,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20).copyWith(
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: isRerouting
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(width: 16),
                    Text('Rerouting...', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            )
          : route == null
              ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          route!.durationInTrafficText,
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            route!.totalDistanceText,
                            style: const TextStyle(color: Colors.white70, fontSize: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: onEndNavigation,
                            icon: const Icon(Icons.close, color: Colors.white),
                            label: const Text('End Navigation', style: TextStyle(fontSize: 18, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class TurnByTurnBanner extends StatelessWidget {
  final RouteStep? step;
  final bool isRerouting;

  const TurnByTurnBanner({Key? key, required this.step, required this.isRerouting}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isRerouting) {
       return Container(
         padding: const EdgeInsets.all(16),
         decoration: BoxDecoration(
           color: Colors.red.shade900.withOpacity(0.9),
           borderRadius: BorderRadius.circular(16),
         ),
         child: const Row(
           children: [
             Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
             SizedBox(width: 16),
             Expanded(
               child: Text('Off Route. Recalculating...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
             ),
           ],
         ),
       );
    }

    if (step == null) return const SizedBox();

    IconData maneuverIcon = Icons.straight;
    if (step!.maneuver.contains('right')) maneuverIcon = Icons.turn_right;
    if (step!.maneuver.contains('left')) maneuverIcon = Icons.turn_left;
    if (step!.maneuver.contains('u-turn')) maneuverIcon = Icons.u_turn_left;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(maneuverIcon, color: Colors.white, size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step!.distanceText,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  step!.cleanInstructions,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloatingMapControls extends StatelessWidget {
  final VoidCallback onRecenter;
  final VoidCallback onToggleTraffic;
  final bool isTrafficEnabled;

  const FloatingMapControls({
    Key? key,
    required this.onRecenter,
    required this.onToggleTraffic,
    required this.isTrafficEnabled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'traffic',
          backgroundColor: isTrafficEnabled ? Colors.cyanAccent : Colors.grey.shade800,
          onPressed: onToggleTraffic,
          child: Icon(Icons.traffic, color: isTrafficEnabled ? Colors.black : Colors.white),
        ),
        const SizedBox(height: 16),
        FloatingActionButton(
          heroTag: 'recenter',
          backgroundColor: Colors.white,
          onPressed: onRecenter,
          child: const Icon(Icons.my_location, color: Colors.blueAccent),
        ),
      ],
    );
  }
}
