export interface Location {
  latitude: number;
  longitude: number;
}

export interface TraumaCenter {
  id: string;
  name: string;
  location: Location;
  distanceString: string; // Placeholder for now, e.g. "2.4 km away"
}
