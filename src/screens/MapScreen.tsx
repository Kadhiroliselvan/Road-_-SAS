import React, { useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import { MapProvider } from '../components/map/MapProvider';
import { BottomPanel } from '../components/ui/BottomPanel';
import { SOSButton } from '../components/ui/SOSButton';
import { TopOverlay } from '../components/ui/TopOverlay';
import { LocationService } from '../services/LocationService';
import { NetworkService } from '../services/NetworkService';

export const MapScreen = () => {
  useEffect(() => {
    // Start watching network status
    NetworkService.startMonitoring();
    // Request location
    LocationService.requestAndGetLocation();

    return () => {
      NetworkService.stopMonitoring();
    };
  }, []);

  return (
    <View style={styles.container}>
      {/* Layer 1: Map */}
      <MapProvider />

      {/* 
        Layer 2: UI Overlays 
        These sit on top of the map using absolute positioning.
      */}
      <TopOverlay />
      
      <SOSButton />
      
      <BottomPanel />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000', // Black fallback before map loads
  },
});
