import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationDataResult {
  final String latitude;
  final String longitude;
  final String address;

  const LocationDataResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

class LocationService {
  LocationService._();

  /// Fetches current GPS location and reverse geocoded address.
  /// Falls back safely with empty strings if permissions are denied or GPS is unavailable.
  static Future<LocationDataResult> getCurrentLocationData() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) {
          print("[LocationService] Location services are disabled on device.");
        }
        return const LocationDataResult(latitude: '', longitude: '', address: '');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) {
            print("[LocationService] Location permission was denied.");
          }
          return const LocationDataResult(latitude: '', longitude: '', address: '');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (kDebugMode) {
          print("[LocationService] Location permissions are permanently denied.");
        }
        return const LocationDataResult(latitude: '', longitude: '', address: '');
      }

      // Query current position with a timeout so network login is never delayed indefinitely
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final String lat = position.latitude.toString();
      final String lon = position.longitude.toString();
      String address = '';

      try {
        final List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 4));

        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final List<String> addressParts = [
            if (p.name != null && p.name!.isNotEmpty && p.name != p.subLocality) p.name!,
            if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
            if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
            if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) p.administrativeArea!,
            if (p.country != null && p.country!.isNotEmpty) p.country!,
          ];
          address = addressParts.toSet().join(', ');
        }
      } catch (e) {
        if (kDebugMode) {
          print("[LocationService] Reverse geocoding error: $e");
        }
        address = "$lat, $lon";
      }

      if (kDebugMode) {
        print("[LocationService] Location captured -> Lat: $lat, Lon: $lon, Address: $address");
      }

      return LocationDataResult(
        latitude: lat,
        longitude: lon,
        address: address,
      );
    } catch (e) {
      if (kDebugMode) {
        print("[LocationService] Error fetching location: $e");
      }
      return const LocationDataResult(latitude: '', longitude: '', address: '');
    }
  }
}
