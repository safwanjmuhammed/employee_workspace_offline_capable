import 'package:geolocator/geolocator.dart';

enum LocationSimulationMode {
  realGps('Real GPS'),
  insideOffice('Simulated: Inside Office (25 m)'),
  outsideOffice('Simulated: Outside Office (~1.4 km)'),
  permissionDenied('Simulated: Permission Denied'),
  permissionPermanentlyDenied('Simulated: Permanently Denied'),
  serviceDisabled('Simulated: Location Service Off'),
  unavailable('Simulated: GPS Unavailable');

  const LocationSimulationMode(this.label);
  final String label;
}

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters = 10.0,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  const LocationSuccess(this.point);
  final GeoPoint point;
}

class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied();
}

class LocationPermissionPermanentlyDenied extends LocationResult {
  const LocationPermissionPermanentlyDenied();
}

class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable([this.reason]);
  final String? reason;
}

abstract interface class LocationService {
  Future<LocationResult> getCurrentLocation({
    required double officeLat,
    required double officeLng,
  });

  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// Switches between real [Geolocator] and configurable simulated modes.
class ConfigurableLocationService implements LocationService {
  ConfigurableLocationService({
    required LocationSimulationMode Function() modeProvider,
  }) : _modeProvider = modeProvider;

  final LocationSimulationMode Function() _modeProvider;

  @override
  Future<LocationResult> getCurrentLocation({
    required double officeLat,
    required double officeLng,
  }) async {
    switch (_modeProvider()) {
      case LocationSimulationMode.insideOffice:
        // ~25 m north-east of the configured office coordinates.
        return LocationSuccess(
          GeoPoint(
            latitude: officeLat + 0.00018,
            longitude: officeLng + 0.00014,
            accuracyMeters: 8.0,
          ),
        );
      case LocationSimulationMode.outsideOffice:
        // ~1.4 km away from the configured office coordinates.
        return LocationSuccess(
          GeoPoint(
            latitude: officeLat + 0.010,
            longitude: officeLng + 0.008,
            accuracyMeters: 12.0,
          ),
        );
      case LocationSimulationMode.permissionDenied:
        return const LocationPermissionDenied();
      case LocationSimulationMode.permissionPermanentlyDenied:
        return const LocationPermissionPermanentlyDenied();
      case LocationSimulationMode.serviceDisabled:
        return const LocationServiceDisabled();
      case LocationSimulationMode.unavailable:
        return const LocationUnavailable('Simulated GPS signal unavailable.');
      case LocationSimulationMode.realGps:
        return _fetchRealGps();
    }
  }

  Future<LocationResult> _fetchRealGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationPermissionDenied();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationPermissionPermanentlyDenied();
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationSuccess(
        GeoPoint(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracyMeters: pos.accuracy,
        ),
      );
    } catch (e) {
      return LocationUnavailable(e.toString());
    }
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
