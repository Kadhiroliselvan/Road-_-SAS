import React, { useEffect } from 'react';
import { StyleSheet, View, Text } from 'react-native';
import Mapbox, { MapView, Camera, PointAnnotation, UserLocation } from '@rnmapbox/maps';
import { useAppStore } from '../../store/useAppStore';

// Initialize Mapbox token here (should be in .env in production)
// Mapbox.setAccessToken('YOUR_PUBLIC_ACCESS_TOKEN');

export const MapProvider = () => {
  const { userLocation, traumaCenters, networkMode } = useAppStore();

  useEffect(() => {
    Mapbox.setTelemetryEnabled(false);
  }, []);

  // Chennai default coordinates
  const defaultCoordinates = [80.2707, 13.0827]; // [longitude, latitude]

  // We rely on Mapbox's automatic offline cache. If networkMode is 'offline', 
  // Mapbox will transparently use the downloaded pack that matches the current region/style.
  
  return (
    <View style={styles.container}>
      <MapView 
        style={styles.map} 
        styleURL={Mapbox.StyleURL.Street}
        logoEnabled={false}
      >
        <Camera
          zoomLevel={12} // Start slightly more zoomed out to see the offline area
          centerCoordinate={
            userLocation 
              ? [userLocation.longitude, userLocation.latitude] 
              : defaultCoordinates
          }
          animationMode="flyTo"
          animationDuration={2000}
        />

        {/* User Location */}
        {userLocation && (
          <UserLocation
             visible={true}
             showsUserHeadingIndicator={true}
          />
        )}

        {/* Trauma Center Markers */}
        {traumaCenters.map((center) => (
          <PointAnnotation
            key={center.id}
            id={center.id}
            coordinate={[center.location.longitude, center.location.latitude]}
          >
            <View style={styles.markerContainer}>
              <Text style={styles.markerText}>🏥</Text>
            </View>
          </PointAnnotation>
        ))}
      </MapView>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1E1E1E', // Dark fallback
  },
  map: {
    flex: 1,
  },
  markerContainer: {
    backgroundColor: 'white',
    borderRadius: 20,
    padding: 5,
    borderWidth: 2,
    borderColor: '#E63946',
  },
  markerText: {
    fontSize: 20,
  }
});
