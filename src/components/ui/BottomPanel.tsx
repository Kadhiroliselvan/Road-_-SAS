import React, { useEffect } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, ActivityIndicator } from 'react-native';
import { useAppStore } from '../../store/useAppStore';
import { Navigation, MapPin, DownloadCloud, CheckCircle } from 'lucide-react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { OfflineTileService } from '../../services/OfflineTileService';

const CACHE_KEY = '@trauma_centers_cache';

export const BottomPanel = () => {
  const { 
    traumaCenters, 
    setTraumaCenters, 
    networkMode, 
    offlineDownloadState,
    userLocation
  } = useAppStore();

  useEffect(() => {
    // Simulate fetching logic
    const fetchCenters = async () => {
      try {
        if (networkMode === 'offline' || networkMode === 'sos') {
          // Load from cache first if offline
          const cached = await AsyncStorage.getItem(CACHE_KEY);
          if (cached) {
            setTraumaCenters(JSON.parse(cached));
          }
        } else {
          // If online, we would fetch from API here.
          // For now, mock data is already in store, so let's just cache it.
          await AsyncStorage.setItem(CACHE_KEY, JSON.stringify(traumaCenters));
        }
      } catch (e) {
        console.error('Error caching trauma centers:', e);
      }
    };
    fetchCenters();
  }, [networkMode]); // Re-run when network mode changes

  const handleDownloadMap = () => {
    if (userLocation) {
      OfflineTileService.downloadRegion(userLocation.latitude, userLocation.longitude);
    } else {
      console.warn("No user location to center download.");
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.dragHandle} />
      
      {/* Offline Download Header */}
      <View style={styles.headerRow}>
        <Text style={styles.title}>Nearest Trauma Centers</Text>
        
        {networkMode === 'online' && offlineDownloadState.status !== 'ready' && (
          <TouchableOpacity style={styles.downloadButton} onPress={handleDownloadMap}>
            {offlineDownloadState.status === 'downloading' ? (
              <View style={styles.downloadingContainer}>
                <ActivityIndicator size="small" color="#1D4ED8" />
                <Text style={styles.downloadText}>{offlineDownloadState.progress}%</Text>
              </View>
            ) : (
              <>
                <DownloadCloud color="#1D4ED8" size={16} />
                <Text style={styles.downloadText}>Download Map</Text>
              </>
            )}
          </TouchableOpacity>
        )}

        {offlineDownloadState.status === 'ready' && (
           <View style={styles.readyContainer}>
             <CheckCircle color="#10B981" size={16} />
             <Text style={styles.readyText}>Offline Ready</Text>
           </View>
        )}
      </View>
      
      <FlatList
        data={traumaCenters}
        keyExtractor={(item) => item.id}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.listContainer}
        renderItem={({ item }) => (
          <TouchableOpacity style={styles.card} activeOpacity={0.8}>
            <View style={styles.cardInfo}>
              <View style={styles.iconContainer}>
                <MapPin color="#E63946" size={24} />
              </View>
              <View>
                <Text style={styles.hospitalName}>{item.name}</Text>
                <Text style={styles.distanceText}>{item.distanceString}</Text>
              </View>
            </View>
            
            <TouchableOpacity style={styles.routeButton}>
              <Navigation color="#FFFFFF" size={20} />
            </TouchableOpacity>
          </TouchableOpacity>
        )}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#FFFFFF',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    height: '40%',
    paddingHorizontal: 20,
    paddingTop: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: -2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 20,
  },
  dragHandle: {
    width: 40,
    height: 4,
    backgroundColor: '#D1D5DB',
    borderRadius: 2,
    alignSelf: 'center',
    marginBottom: 16,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: {
    fontSize: 18,
    fontWeight: '700',
    color: '#111827',
  },
  downloadButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#DBEAFE', // Light blue
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  downloadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  downloadText: {
    color: '#1D4ED8',
    fontSize: 12,
    fontWeight: '600',
    marginLeft: 6,
  },
  readyContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#D1FAE5', // Light green
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
  },
  readyText: {
    color: '#065F46',
    fontSize: 12,
    fontWeight: '600',
    marginLeft: 6,
  },
  listContainer: {
    paddingBottom: 20,
  },
  card: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: '#F3F4F6',
    borderRadius: 16,
    padding: 16,
    marginBottom: 12,
  },
  cardInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  iconContainer: {
    backgroundColor: '#FEE2E2',
    padding: 10,
    borderRadius: 12,
    marginRight: 12,
  },
  hospitalName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1F2937',
    marginBottom: 4,
  },
  distanceText: {
    fontSize: 14,
    color: '#6B7280',
  },
  routeButton: {
    backgroundColor: '#1D4ED8',
    padding: 12,
    borderRadius: 12,
  }
});
