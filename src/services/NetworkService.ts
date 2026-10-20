import NetInfo, { NetInfoState } from '@react-native-community/netinfo';
import { useAppStore } from '../store/useAppStore';
import { OfflineTileService } from './OfflineTileService';

/**
 * Service to monitor network changes and update app network mode.
 */
export class NetworkService {
  private static unsubscribe: (() => void) | null = null;

  /**
   * Starts listening to network state changes.
   */
  static startMonitoring() {
    if (this.unsubscribe) return; // Already monitoring

    this.unsubscribe = NetInfo.addEventListener(state => {
      this.handleNetworkChange(state);
    });
    
    // Initial check
    NetInfo.fetch().then(state => this.handleNetworkChange(state));
  }

  /**
   * Stops listening to network state changes.
   */
  static stopMonitoring() {
    if (this.unsubscribe) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  /**
   * Logic to determine if we are online, offline, or sos mode
   */
  private static async handleNetworkChange(state: NetInfoState) {
    const { setNetworkMode } = useAppStore.getState();
    const isConnected = state.isConnected && state.isInternetReachable !== false;

    if (isConnected) {
      // Connected + we could have tiles ready or not, but we have internet -> online
      setNetworkMode('online');
    } else {
      // Disconnected: check if we have any offline tiles downloaded
      const packs = await OfflineTileService.listRegions();
      
      if (packs && packs.length > 0) {
        // Disconnected + tiles ready -> offline mode
        setNetworkMode('offline');
      } else {
        // Disconnected + no tiles -> sos mode (worst case scenario)
        setNetworkMode('sos');
      }
    }
  }
}
