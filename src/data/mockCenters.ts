import { TraumaCenter } from '../models/TraumaCenter';

export const MOCK_TRAUMA_CENTERS: TraumaCenter[] = [
  {
    id: '1',
    name: 'Apollo Main Hospital',
    location: { latitude: 13.0604, longitude: 80.2541 },
    distanceString: '1.2 km - 5 mins',
  },
  {
    id: '2',
    name: 'Rajiv Gandhi General Hospital',
    location: { latitude: 13.0827, longitude: 80.2707 },
    distanceString: '4.5 km - 12 mins',
  },
  {
    id: '3',
    name: 'Kauvery Hospital',
    location: { latitude: 13.0333, longitude: 80.2608 },
    distanceString: '3.8 km - 10 mins',
  },
];
