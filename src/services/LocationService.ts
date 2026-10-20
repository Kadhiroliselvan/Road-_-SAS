import * as Location from 'expo-location';
import { useAppStore } from '../store/useAppStore';

/**
 * Service to handle device location requests.
 * Future-proofing: We can add background tracking logic (startLocationUpdatesAsync) here later.
 */
export class LocationService {
  /**
   * Request permissions and get current location.
   */
  static async requestAndGetLocation() {
    const { setGpsActive, setUserLocation } = useAppStore.getState();

    try {
      setGpsActive(false); // Indicate we are trying to get it
      let { status } = await Location.requestForegroundPermissionsAsync();
      
      if (status !== 'granted') {
        console.warn('Permission to access location was denied');
        return;
      }

      // Get current location (low accuracy first for speed, then high if needed later)
      let location = await Location.getCurrentPositionAsync({});
      
      setUserLocation({
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
      });
      setGpsActive(true);

    } catch (error) {
      console.error('Error fetching location:', error);
      setGpsActive(false);
    }
  }
}
