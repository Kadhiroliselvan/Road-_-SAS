import { create } from 'zustand';
import { TraumaCenter, Location } from '../models/TraumaCenter';
import { MOCK_TRAUMA_CENTERS } from '../data/mockCenters';

export type NetworkMode = 'online' | 'offline' | 'sos';

export type OfflineDownloadState = {
  status: 'idle' | 'downloading' | 'ready' | 'error';
  progress: number; // 0 to 100
};

interface AppState {
  userLocation: Location | null;
  gpsActive: boolean;
  traumaCenters: TraumaCenter[];
  networkMode: NetworkMode;
  offlineDownloadState: OfflineDownloadState;
  
  // Actions
  setUserLocation: (location: Location | null) => void;
  setGpsActive: (active: boolean) => void;
  setTraumaCenters: (centers: TraumaCenter[]) => void;
  setNetworkMode: (mode: NetworkMode) => void;
  setOfflineDownloadState: (state: Partial<OfflineDownloadState>) => void;
}

export const useAppStore = create<AppState>((set) => ({
  userLocation: null,
  gpsActive: false,
  traumaCenters: MOCK_TRAUMA_CENTERS, // Initialize with mock data initially
  networkMode: 'online', // Default to online
  offlineDownloadState: { status: 'idle', progress: 0 },
  
  setUserLocation: (location) => set({ userLocation: location }),
  setGpsActive: (active) => set({ gpsActive: active }),
  setTraumaCenters: (centers) => set({ traumaCenters: centers }),
  setNetworkMode: (mode) => set({ networkMode: mode }),
  setOfflineDownloadState: (state) => 
    set((prev) => ({ 
      offlineDownloadState: { ...prev.offlineDownloadState, ...state } 
    })),
}));
