#include <Arduino.h>
#include <Wire.h>
#include <math.h>
#include <stdlib.h>
#include "driver/i2s.h"

#include <Adafruit_LIS3DH.h>
#include <Adafruit_Sensor.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =====================================================
// INMP441 + XIAO ESP32C3
// =====================================================

#define I2S_SCK D3
#define I2S_WS  D2
#define I2S_SD  D4
#define I2S_PORT I2S_NUM_0

// =====================================================
// LIS3DH + XIAO ESP32C3
// =====================================================

#define I2C_SDA D7
#define I2C_SCL D8

Adafruit_LIS3DH lis = Adafruit_LIS3DH();

// =====================================================
// Battery
// BAT+ --- 200kΩ --- A0 --- 200kΩ --- GND
// =====================================================

#define BATTERY_ADC_PIN A0
#define BATTERY_READ_INTERVAL_MS 2000

float batteryVoltage = 0.0f;
int batteryPercent = 0;
unsigned long lastBatteryReadTime = 0;

const int BATTERY_TABLE_SIZE = 15;

float voltageTable[BATTERY_TABLE_SIZE] = {
  4.20, 4.15, 4.11, 4.08, 4.02,
  3.98, 3.95, 3.91, 3.87, 3.85,
  3.80, 3.75, 3.70, 3.60, 3.30
};

int percentTable[BATTERY_TABLE_SIZE] = {
  100, 95, 90, 85, 80,
  70, 60, 50, 40, 30,
  20, 15, 10, 5, 0
};

// =====================================================
// BLE
// =====================================================

#define BLE_DEVICE_NAME "CadenceMic"

#define SERVICE_UUID   "12345678-1234-1234-1234-1234567890ab"
#define DATA_CHAR_UUID "abcdefab-1234-5678-1234-abcdefabcdef"

// =====================================================
// Mic
// =====================================================

#define SAMPLE_RATE 16000
#define BUFFER_LEN 128

#define NOISE_FLOOR 20.0f
#define AMBIENT_WINDOW_MS 5000
#define AMBIENT_LOW_PERCENT 20
#define AMBIENT_MAX_SAMPLES 640
#define AMBIENT_SMOOTH_ALPHA 0.70f

// =====================================================
// Step Detection
// =====================================================

#define ACCEL_SAMPLE_INTERVAL_MS 20

// The walking peaks in the measured signal are approximately 8 to 24.
#define STEP_PEAK_THRESHOLD 2.50f
#define ACCEL_BASELINE_ALPHA 0.96f
#define ACCEL_SIGNAL_ALPHA 0.55f
#define MIN_STEP_GAP_MS 280
#define MIN_BPM_STEP_INTERVAL_MS 300
#define MAX_BPM_STEP_INTERVAL_MS 1500
#define BPM_INTERVAL_BUFFER_SIZE 6
#define BPM_MIN_INTERVAL_SAMPLES 3
#define BPM_UPDATE_INTERVAL_MS 2000

#define BPM_TIMEOUT_MS 4000
#define BLE_SEND_INTERVAL_MS 500

// Serial Monitor prints one persistent line per detected step.

// =====================================================

float ambientLevel = 0.0f;
float currentLevel = 0.0f;
float ambientSamples[AMBIENT_MAX_SAMPLES];
size_t ambientSampleCount = 0;
unsigned long ambientWindowStartTime = 0;

float accelMagnitude = 9.81f;
float accelBaseline = 9.81f;
float accelRawDelta = 0.0f;
float accelFilteredDelta = 0.0f;
float filteredDeltaPrev1 = 0.0f;
float filteredDeltaPrev2 = 0.0f;

bool stepDetected = false;
unsigned long stepCount = 0;

unsigned long lastStepTime = 0;
unsigned long previousStepTime = 0;
unsigned long lastBleSendTime = 0;
unsigned long lastAccelReadTime = 0;
unsigned long lastPrintedStepCount = 0;
unsigned long bpmIntervals[BPM_INTERVAL_BUFFER_SIZE] = {0};
size_t bpmIntervalCount = 0;
size_t bpmIntervalIndex = 0;
unsigned long lastBpmUpdateTime = 0;

float bpm = 0.0f;

BLECharacteristic *dataCharacteristic;
bool deviceConnected = false;

// =====================================================
// BLE Callback
// =====================================================

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) {
    deviceConnected = true;
  }

  void onDisconnect(BLEServer *server) {
    deviceConnected = false;
    server->startAdvertising();
  }
};

// =====================================================
// Battery Functions
// =====================================================

float readBatteryVoltage() {
  const int samples = 16;
  long sumMv = 0;

  for (int i = 0; i < samples; i++) {
    sumMv += analogReadMilliVolts(BATTERY_ADC_PIN);
    delay(2);
  }

  float adcMv = sumMv / (float)samples;
  float batteryV = (adcMv * 2.0f) / 1000.0f;

  return batteryV;
}

int voltageToPercent(float voltage) {
  if (voltage >= voltageTable[0]) return 100;
  if (voltage <= voltageTable[BATTERY_TABLE_SIZE - 1]) return 0;

  for (int i = 0; i < BATTERY_TABLE_SIZE - 1; i++) {
    float vHigh = voltageTable[i];
    float vLow = voltageTable[i + 1];

    int pHigh = percentTable[i];
    int pLow = percentTable[i + 1];

    if (voltage <= vHigh && voltage >= vLow) {
      float ratio = (voltage - vLow) / (vHigh - vLow);
      int percent = pLow + ratio * (pHigh - pLow);
      return percent;
    }
  }

  return 0;
}

void updateBattery() {
  unsigned long now = millis();

  if (now - lastBatteryReadTime < BATTERY_READ_INTERVAL_MS) {
    return;
  }

  lastBatteryReadTime = now;

  batteryVoltage = readBatteryVoltage();
  batteryPercent = voltageToPercent(batteryVoltage);
}

// =====================================================
// BLE Setup
// =====================================================

void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);

  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  dataCharacteristic = service->createCharacteristic(
    DATA_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  dataCharacteristic->addDescriptor(new BLE2902());

  dataCharacteristic->setValue("{\"bpm\":0,\"ambient\":0,\"battery\":0,\"voltage\":0}");

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

// =====================================================
// I2S Setup
// =====================================================

void setupI2S() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = BUFFER_LEN,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_PORT, &pin_config);
  i2s_zero_dma_buffer(I2S_PORT);
}

// =====================================================
// LIS3DH Setup
// =====================================================

void setupLIS3DH() {
  Wire.begin(I2C_SDA, I2C_SCL);

  if (!lis.begin(0x18)) {
    if (!lis.begin(0x19)) {
      while (1) {
        delay(1000);
      }
    }
  }

  lis.setRange(LIS3DH_RANGE_4_G);
  lis.setDataRate(LIS3DH_DATARATE_100_HZ);

  sensors_event_t event;
  lis.getEvent(&event);

  accelMagnitude = sqrtf(
    event.acceleration.x * event.acceleration.x +
    event.acceleration.y * event.acceleration.y +
    event.acceleration.z * event.acceleration.z
  );
  accelBaseline = accelMagnitude;
}

// =====================================================
// Mic Reading
// =====================================================

float readMicLevel() {
  int32_t samples[BUFFER_LEN];
  size_t bytesRead = 0;

  esp_err_t result = i2s_read(
    I2S_PORT,
    samples,
    sizeof(samples),
    &bytesRead,
    100 / portTICK_PERIOD_MS
  );

  if (result != ESP_OK || bytesRead == 0) {
    return 0;
  }

  int count = bytesRead / sizeof(int32_t);
  double sampleSum = 0.0;

  for (int i = 0; i < count; i++) {
    int32_t audio = samples[i] >> 14;
    sampleSum += audio;
  }

  double mean = sampleSum / count;
  double squareSum = 0.0;

  for (int i = 0; i < count; i++) {
    double centeredSample = (samples[i] >> 14) - mean;
    squareSum += centeredSample * centeredSample;
  }

  float level = sqrtf((float)(squareSum / count));

  if (level < NOISE_FLOOR) {
    level = 0;
  }

  return level;
}

// =====================================================
// Ambient Noise
// Average the quietest 20 percent of samples in each
// five-second window, then smooth between windows.
// =====================================================

int compareFloat(const void *left, const void *right) {
  float a = *(const float *)left;
  float b = *(const float *)right;
  return (a > b) - (a < b);
}

void updateAmbientNoise(float level) {
  unsigned long now = millis();

  if (ambientSampleCount < AMBIENT_MAX_SAMPLES) {
    ambientSamples[ambientSampleCount++] = level;
  }

  if (now - ambientWindowStartTime < AMBIENT_WINDOW_MS) {
    return;
  }

  ambientWindowStartTime = now;

  if (ambientSampleCount == 0) {
    return;
  }

  qsort(
    ambientSamples,
    ambientSampleCount,
    sizeof(ambientSamples[0]),
    compareFloat
  );

  size_t quietSampleCount =
    (ambientSampleCount * AMBIENT_LOW_PERCENT) / 100;

  if (quietSampleCount == 0) {
    quietSampleCount = 1;
  }

  double quietSum = 0.0;

  for (size_t i = 0; i < quietSampleCount; i++) {
    quietSum += ambientSamples[i];
  }

  float windowAmbient = quietSum / quietSampleCount;

  if (ambientLevel == 0.0f) {
    ambientLevel = windowAmbient;
  } else {
    ambientLevel =
      ambientLevel * AMBIENT_SMOOTH_ALPHA +
      windowAmbient * (1.0f - AMBIENT_SMOOTH_ALPHA);
  }

  ambientSampleCount = 0;
}

// =====================================================
// Accelerometer Step Detection
// Local peak detection counts one peak per step.
// The minimum gap rejects secondary peaks from the same impact.
// =====================================================

void registerStep(unsigned long now) {
  stepDetected = true;
  stepCount++;

  previousStepTime = lastStepTime;
  lastStepTime = now;

  if (previousStepTime == 0) {
    return;
  }

  unsigned long interval = lastStepTime - previousStepTime;

  if (
    interval < MIN_BPM_STEP_INTERVAL_MS ||
    interval > MAX_BPM_STEP_INTERVAL_MS
  ) {
    bpmIntervalCount = 0;
    bpmIntervalIndex = 0;
    return;
  }

  bpmIntervals[bpmIntervalIndex] = interval;
  bpmIntervalIndex =
    (bpmIntervalIndex + 1) % BPM_INTERVAL_BUFFER_SIZE;

  if (bpmIntervalCount < BPM_INTERVAL_BUFFER_SIZE) {
    bpmIntervalCount++;
  }

  if (
    bpmIntervalCount < BPM_MIN_INTERVAL_SAMPLES ||
    now - lastBpmUpdateTime < BPM_UPDATE_INTERVAL_MS
  ) {
    return;
  }

  unsigned long intervalSum = 0;

  for (size_t i = 0; i < bpmIntervalCount; i++) {
    intervalSum += bpmIntervals[i];
  }

  float averageInterval =
    intervalSum / (float)bpmIntervalCount;

  bpm = 60000.0f / averageInterval;
  lastBpmUpdateTime = now;
}

void updateAccelStepDetection() {
  unsigned long now = millis();

  stepDetected = false;

  if (now - lastAccelReadTime < ACCEL_SAMPLE_INTERVAL_MS) {
    return;
  }

  lastAccelReadTime = now;

  sensors_event_t event;
  lis.getEvent(&event);

  float ax = event.acceleration.x;
  float ay = event.acceleration.y;
  float az = event.acceleration.z;

  accelMagnitude = sqrtf(ax * ax + ay * ay + az * az);

  accelBaseline =
    accelBaseline * ACCEL_BASELINE_ALPHA +
    accelMagnitude * (1.0f - ACCEL_BASELINE_ALPHA);

  accelRawDelta = fabsf(accelMagnitude - accelBaseline);

  filteredDeltaPrev2 = filteredDeltaPrev1;
  filteredDeltaPrev1 = accelFilteredDelta;

  accelFilteredDelta =
    accelFilteredDelta * ACCEL_SIGNAL_ALPHA +
    accelRawDelta * (1.0f - ACCEL_SIGNAL_ALPHA);

  bool isStepPeak =
    filteredDeltaPrev1 > filteredDeltaPrev2 &&
    filteredDeltaPrev1 >= accelFilteredDelta &&
    filteredDeltaPrev1 >= STEP_PEAK_THRESHOLD;

  if (isStepPeak && now - lastStepTime >= MIN_STEP_GAP_MS) {
    registerStep(now);
  }

  if (lastStepTime > 0 && now - lastStepTime > BPM_TIMEOUT_MS) {
    bpm = 0.0f;
    bpmIntervalCount = 0;
    bpmIntervalIndex = 0;
  }
}

// =====================================================
// BLE Send
// =====================================================

void sendBLEData() {
  if (!deviceConnected) return;

  String data = "{";
  data += "\"bpm\":";
  data += String(bpm, 0);
  data += ",\"ambient\":";
  data += String(ambientLevel, 1);
  data += ",\"battery\":";
  data += batteryPercent;
  data += ",\"voltage\":";
  data += String(batteryVoltage, 2);
  data += "}";

  dataCharacteristic->setValue(data.c_str());
  dataCharacteristic->notify();
}

// =====================================================
// Serial Monitor Output
// Prints exactly one line for each newly detected step.
// =====================================================

void outputStepStatus() {
  if (stepCount == 0 || stepCount == lastPrintedStepCount) {
    return;
  }

  lastPrintedStepCount = stepCount;

  Serial.print("STEP | count: ");
  Serial.print(stepCount);
  Serial.print(" | bpm: ");
  Serial.print(bpm, 0);
  Serial.print(" | ambientNoise: ");
  Serial.println(ambientLevel, 1);
}

// =====================================================
// Setup
// =====================================================

void setup() {
  Serial.begin(115200);
  delay(2000);

  setupI2S();
  setupLIS3DH();
  setupBLE();

  ambientWindowStartTime = millis();
  lastBatteryReadTime = millis() - BATTERY_READ_INTERVAL_MS;
  updateBattery();
}

// =====================================================
// Loop
// =====================================================

void loop() {
  currentLevel = readMicLevel();
  updateAmbientNoise(currentLevel);

  updateAccelStepDetection();
  updateBattery();

  unsigned long now = millis();

  if (now - lastBleSendTime >= BLE_SEND_INTERVAL_MS) {
    lastBleSendTime = now;
    sendBLEData();
  }

  outputStepStatus();
}
