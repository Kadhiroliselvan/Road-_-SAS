import Mapbox from '@rnmapbox/maps';
import { useAppStore } from '../store/useAppStore';

/**
 * Service to handle downloading offline Mapbox tiles for regions.
 */
export class OfflineTileService {
  /**
   * Generates a bounding box around a center coordinate.
   * Very simplified calculation for ~15km radius.
   * 1 degree latitude ~ 111km.
   */
  private static getBoundingBox(lat: number, lng: number, radiusKm: number = 15) {
    const latDelta = radiusKm / 111;
    // Longitude shrinks as we move away from equator, approx using cos(lat)
    const lngDelta = radiusKm / (111 * Math.cos(lat * (Math.PI / 180)));

    return [
      [lng + lngDelta, lat + latDelta], // North East [lng, lat]
      [lng - lngDelta, lat - latDelta], // South West [lng, lat]
    ];
  }

  /**
   * Downloads an offline region around the specified coordinates.
   */
  static async downloadRegion(lat: number, lng: number) {
    const { setOfflineDownloadState } = useAppStore.getState();
    const packName = `roadsos_region_${lat.toFixed(4)}_${lng.toFixed(4)}`;

    try {
      setOfflineDownloadState({ status: 'downloading', progress: 0 });

      const bounds = this.getBoundingBox(lat, lng);

      const offlineRegion = {
        name: packName,
        styleURL: Mapbox.StyleURL.Street,
        bounds: bounds,
        minZoom: 10,
        maxZoom: 15,
      };

      // Create and start the pack download
      await Mapbox.offlineManager.createPack(
        offlineRegion,
        (pack, status) => {
          // Progress listener
          if (status.percentage) {
            setOfflineDownloadState({ 
              status: 'downloading', 
              progress: Math.round(status.percentage) 
            });
          }
        },
        (pack, err) => {
          // Error listener
          console.error('Offline pack error:', err);
          setOfflineDownloadState({ status: 'error' });
        }
      );

      // Once complete (createPack resolves when done)
      setOfflineDownloadState({ status: 'ready', progress: 100 });
      console.log(`Successfully downloaded offline pack: ${packName}`);

    } catch (error) {
      console.error('Failed to start offline download:', error);
      setOfflineDownloadState({ status: 'error' });
    }
  }

  /**
   * List all downloaded offline regions.
   */
  static async listRegions() {
    try {
      const packs = await Mapbox.offlineManager.getPacks();
      return packs;
    } catch (error) {
      console.error('Failed to list packs:', error);
      return [];
    }
  }

  /**
   * Delete an offline region.
   */
  static async deleteRegion(packName: string) {
    try {
      await Mapbox.offlineManager.deletePack(packName);
      console.log(`Deleted offline pack: ${packName}`);
    } catch (error) {
      console.error(`Failed to delete pack ${packName}:`, error);
    }
  }
}
