# InTune 🎧

InTune is my MSc Connected Environments dissertation project at UCL. It explores how an exercise music system can respond to three parts of the user's context: movement cadence, ambient sound and geographic location.

The project brings together a wearable sensing device, BLE communication, a Flutter app and an offline music-processing pipeline. The wearable measures cadence and relative sound level, while the app uses OpenStreetMap data to understand the surrounding environment. These inputs are then used to rank music by tempo and contextual fit.

![InTune interface](landing/assets/in-tune-hero.png)

## How the system works

1. An LIS3DH accelerometer estimates the user's movement cadence.
2. An INMP441 microphone measures the relative ambient sound level. Raw audio is not stored.
3. A XIAO ESP32-C3 sends both readings to the Flutter app through BLE.
4. The app uses GPS and nearby OpenStreetMap features to classify the environment.
5. Tracks are ranked using tempo fit, CLAP similarity and metadata scores.
6. Cadence and place guide music selection, while ambient sound adjusts playback volume.

The music data is processed in advance, so the phone does not need to run CLAP or another machine-learning model during exercise.

## Repository structure 📁

| Folder | Contents |
| --- | --- |
| [`App_Research`](App_Research/) | Main Flutter app with GPS, Overpass API, BLE input and music recommendation |
| [`App_Exhibition`](App_Exhibition/) | Landscape version developed for the final exhibition |
| [`Physical_Device`](Physical_Device/) | Firmware for the wearable sensing device |
| [`Music_Preprocessing`](Music_Preprocessing/) | Python scripts for BPM, CLAP and metadata preprocessing |
| [`PCB`](PCB/) | Custom PCB design and Gerber files |
| [`enclosures`](enclosures/) | 3D-printable enclosure models |
| [`sensor_test`](sensor_test/) | Earlier sensor tests and calibration work |
| [`Document`](Document/) | Dissertation materials, meeting notes and figures |
| [`landing`](landing/) | Project webpage and Android APK |

## Flutter apps 📱

The repository contains two versions of the app.

`App_Research` is the main research prototype. It supports live GPS, Overpass API queries, BLE sensor input, music recommendation and playback. Mock controls are also included, so the recommendation flow can still be tested without the wearable or a live location signal.

`App_Exhibition` keeps the same core system but uses a landscape layout and manual map selection. This version was made for a tablet-based exhibition setup, where the location and sensor inputs needed to be easy to demonstrate.

To run either app, install Flutter with Dart 3.10 or later and connect an Android device.

```bash
cd App_Research
flutter pub get
flutter run
```

For the exhibition version, replace `App_Research` with `App_Exhibition`.

## Music preprocessing 🎵

The app reads a local JSON music library. The preprocessing pipeline extracts tempo and source metadata, with optional CLAP scoring for similarity between each track and a set of environmental prompts.

To build the library without CLAP:

```bash
cd Music_Preprocessing
pip install -r requirements.txt
python scripts/preprocess_music.py \
  --input data/raw_music \
  --output data/processed/music_library.json \
  --metadata-only
```

To include CLAP and a metadata prior:

```bash
pip install -r requirements-clap.txt
python scripts/preprocess_music.py \
  --input data/raw_music \
  --output data/processed/music_library.json \
  --metadata-only \
  --use-clap \
  --metadata-prior-weight 0.35
```

More information about the audio sources, configuration files and JSON output is available in the [music preprocessing README](Music_Preprocessing/README.md).

## Hardware 🔧

The final wearable uses a Seeed Studio XIAO ESP32-C3, an LIS3DH accelerometer and an INMP441 microphone. The project began with separate development boards and sensor tests before moving to a custom PCB and a smaller 3D-printed enclosure.

The final firmware is in [`Physical_Device/physical_device_code`](Physical_Device/physical_device_code/). PCB files and enclosure models are included in their respective folders.

## Project status

InTune is a working research prototype rather than a finished consumer product. The current evaluation tests whether the complete sensing and recommendation pipeline works together. It does not yet show how well the system performs across a large group of users, activities and locations.

Future work would need a larger field study, reference cadence measurements and a broader licensed music library. It would also be useful to compare a fixed playlist, cadence-based recommendation and the full context-aware system under the same conditions.

## Links

- [Project webpage](https://cynthiazhangovo.github.io/InTune/)
- [Download the Android APK](https://github.com/CynthiaZHANGovo/Dissertation/releases/latest/download/InTune.apk)
- [GitHub repository](https://github.com/CynthiaZHANGovo/Dissertation)

## Author

Xinyi Zhang

MSc Connected Environments, University College London
