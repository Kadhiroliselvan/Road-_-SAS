import React from 'react';
import { View, Text, StyleSheet, SafeAreaView } from 'react-native';
import { useAppStore } from '../../store/useAppStore';

export const TopOverlay = () => {
  const { gpsActive, networkMode } = useAppStore();

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.container}>
        <Text style={styles.title}>ROADSOS</Text>
        
        <View style={styles.statusContainer}>
          <View 
            style={[
              styles.statusDot, 
              { 
                backgroundColor: 
                  networkMode === 'online' ? '#10B981' : 
                  networkMode === 'offline' ? '#6B7280' : 
                  '#EF4444' // sos
              } 
            ]} 
          />
          <Text style={styles.statusText}>
            {networkMode === 'online' ? 'Online' : 
             networkMode === 'offline' ? 'Offline' : 'SOS Mode'}
          </Text>
        </View>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  safeArea: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 10,
  },
  container: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: '900',
    color: '#111827',
    letterSpacing: 1,
    textShadowColor: 'rgba(255, 255, 255, 0.8)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 2,
  },
  statusContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 4,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  statusText: {
    fontSize: 12,
    fontWeight: '600',
    color: '#374151',
  }
});
