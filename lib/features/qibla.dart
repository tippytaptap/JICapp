import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../core/models.dart';
import '../widgets/common.dart';

class QiblaPage extends StatefulWidget {
  const QiblaPage({super.key});
  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage> {
  double? bearing, heading;
  bool busy = false;
  String? error;
  StreamSubscription<CompassEvent>? compass;
  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Location is switched off.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if ([
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ].contains(permission)) {
        throw StateError(
          'Allow location in your device settings to find Qibla.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      bearing = qiblaBearing(position.latitude, position.longitude);
      await compass?.cancel();
      compass = FlutterCompass.events?.listen(
        (event) {
          if (mounted) setState(() => heading = event.heading);
        },
        onError: (_) {
          if (mounted) setState(() => heading = null);
        },
      );
    } on StateError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Location could not be read. Please try again.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    compass?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentPage(
    title: 'Qibla',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SectionTitle(
          'Turn towards the Kaaba',
          subtitle: 'Location is used on this screen only.',
        ),
        if (bearing != null) ...[
          const SizedBox(height: 48),
          Center(
            child: Transform.rotate(
              angle: (bearing! - (heading ?? 0)) * math.pi / 180,
              child: const Icon(
                Icons.navigation,
                size: 160,
                color: Color(0xffd6af62),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            '${bearing!.round()}° from true north',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            heading == null
                ? 'No compass reading. Use the bearing above with a compass.'
                : 'Keep your phone flat and away from metal. Compass readings may vary.',
            textAlign: TextAlign.center,
          ),
        ],
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: busy ? null : locate,
          child: Text(busy ? 'Finding location…' : 'Find Qibla'),
        ),
      ],
    ),
  );
}
