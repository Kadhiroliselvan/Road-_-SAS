# ROAD SAS - Smart Offline & Online Emergency Assistance and Navigation System

<p align="center">
  <img src="assets/car.png" width="150" alt="ROAD SAS Logo">
</p>

**ROAD SAS** is a reliable emergency assistance and navigation mobile application designed to provide crucial routing to nearby emergency services (Hospitals, Police Stations, Fire Stations, Tow Trucks) regardless of your internet connection. 

During emergencies, network outages and poor visibility can lead to fatal delays. ROAD SAS solves this by seamlessly switching between Online (live traffic via APIs) and Offline (local JSON and stored maps) modes, ensuring help is always just a tap away.

## 🚀 Key Features

* 🌐 **Hybrid Modes**: Operates in both Online (live data & traffic) and Offline (stored local maps & JSON data) modes.
* 🏥 **Nearby Emergency Services**: Instant access to nearby Hospitals, Police, Fire Stations, and Tow services.
* 🚨 **One-Tap SOS**: Dedicated SOS functionality to immediately lock onto the closest emergency service.
* 🧭 **Smart Navigation**: Optimized route calculation.
* 📱 **Intuitive UI**: Clean, accessible design featuring a sliding sidebar and a prominent SOS button.

## 🛠️ Technology Stack

* **Frontend Framework**: Flutter (Dart)
* **Mapping**: `flutter_map`, Mapbox
* **Location & Sensors**: `geolocator`, `sensors_plus`
* **Offline Maps**: MBTiles (`mbtiles`, `vector_map_tiles_mbtiles`, `vector_tile_renderer`)
* **Real-time Communication**: `socket_io_client`
* **Local Storage**: `shared_preferences`, SQLite (`sqflite`, `sqlite3_flutter_libs`)
* **Telephony & TTS**: `telephony`, `flutter_tts`

## 🏗️ System Architecture Deep Dive

ROAD SAS is built on a modular architecture that separates the UI, logic, data, and communication layers to ensure high reliability, especially during network transitions.

### 1. Presentation & State Layer
- **UI Framework**: Built completely in **Flutter**, ensuring a natively compiled, fluid experience. The interface uses a dynamic sliding sidebar and high-contrast alert elements for quick navigation during stressful situations.
- **State Management**: Managed via **Riverpod** (`flutter_riverpod`), allowing the app to efficiently react to connection state changes (online vs. offline) and instantly rebuild only the affected UI components (like map markers or routing overlays).

### 2. Location & Sensing Engine
- **GPS Tracking**: Utilizes `geolocator` to continuously fetch high-accuracy user coordinates, providing the baseline for all map operations.
- **Inertial Sensors**: Integrates `sensors_plus` to monitor the accelerometer and gyroscope. This lays the groundwork for the future TinyML crash detection module by monitoring sudden velocity or impact changes.

### 3. Dual-Mode Mapping Engine
The core innovation of ROAD SAS lies in its hybrid map rendering and routing capabilities:
- **Online Maps**: When a network is available, it hooks into **Mapbox APIs** (via `flutter_map` and HTTP) to fetch live tiles, traffic conditions, and dynamic routes.
- **Offline Maps**: When the network drops, the app switches to a localized map engine. It uses `flutter_map` alongside `vector_map_tiles` to render pre-downloaded **MBTiles** (e.g., `osm-2020-02-10-v3.11_india_chennai.mbtiles`). These tiles are queried at lightning speed using SQLite C-bindings (`sqlite3_flutter_libs`), ensuring fully interactive, zoomable maps without a single byte of internet data.

### 4. Hybrid Data & POI (Point of Interest) Layer
- **Online Routing**: Queries external REST APIs for the absolute fastest route considering current road closures and traffic density.
- **Offline Fallback**: Pre-packaged within the app's assets are highly optimized JSON datasets (`hospitals.json`, `police_simple.json`, etc.). In offline mode, the app parses these files, calculates the Haversine distance relative to the user's GPS coordinates, and plots the nearest emergency hubs directly onto the offline map tiles.

### 5. Real-Time Communication & SOS Module
- **Socket Engine**: Uses `socket_io_client` to maintain a persistent, bidirectional connection with a backend server. This allows for live vehicle tracking, real-time location sharing, and instant SOS broadcasting to a central dashboard.
- **Telephony Fallback**: In the event of a total data blackout, the app utilizes the `telephony` package to trigger direct SMS alerts to saved emergency contacts, bypassing the internet entirely to guarantee message delivery.
- **Voice Feedback**: Uses `flutter_tts` (Text-to-Speech) to provide auditory confirmation when an SOS is sent or to read out navigation instructions, allowing the driver to keep their eyes on the road.

## 🔮 Future Enhancements

* 🧠 **TinyML Integration**: AI-based automatic crash detection using phone sensors (accelerometer/gyroscope).
* 🎙️ **Voice Assistance**: Hands-free operation for driving scenarios.
* 🚑 **Ambulance Tracking**: Real-time ETA updates for dispatched units.
* 📞 **Auto-Dialer**: Automatically call emergency contacts during an SOS event.

## 🏁 Getting Started

To run this project locally:

1. Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
2. Clone this repository.
3. Fetch dependencies:
   ```bash
   flutter pub get
   ```
4. Run the app on an emulator or connected device:
   ```bash
   flutter run
   ```

## 📜 License

This project is developed as part of an academic/hackathon initiative. Please contact the authors for usage rights or contributions.
