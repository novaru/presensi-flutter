import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Location services are turned off. Please enable GPS.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission was denied.';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission is permanently denied. Enable it in app settings.';
    }

    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }
}
