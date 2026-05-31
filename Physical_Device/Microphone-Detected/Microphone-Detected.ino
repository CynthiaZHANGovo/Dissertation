#include <Arduino.h>
#include "driver/i2s.h"

// =====================================================
// INMP441 + XIAO ESP32C3
//
// SCK -> D3
// WS  -> D2
// SD  -> D4
// VDD -> 3V3
// GND -> GND
// L/R -> GND
// =====================================================

#define I2S_SCK D3
#define I2S_WS  D2
#define I2S_SD  D4

#define I2S_PORT I2S_NUM_0

// ===== Adjustable Parameters =====

#define SAMPLE_RATE 16000
#define BUFFER_LEN 128

#define NOISE_FLOOR 20.0f

// Lower = more sensitive
#define STEP_THRESHOLD_MULTIPLIER 2.0f

// Minimum time between steps
#define MIN_STEP_GAP_MS 180

// Reset BPM if no step detected
#define BPM_TIMEOUT_MS 3000

// Ambient smoothing
#define AMBIENT_ALPHA 0.95f

// =====================================================

float ambientLevel = 0.0f;
float currentLevel = 0.0f;

bool stepDetected = false;

unsigned long lastStepTime = 0;
unsigned long previousStepTime = 0;

int bpm = 0;

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

  long long sumAbs = 0;

  for (int i = 0; i < count; i++) {

    int16_t audio = samples[i] >> 14;

    sumAbs += abs(audio);
  }

  float level = (float)sumAbs / count;

  if (level < NOISE_FLOOR) {
    level = 0;
  }

  return level;
}

// =====================================================

void updateStepDetection(float level) {

  unsigned long now = millis();

  stepDetected = false;

  if (ambientLevel == 0) {
    ambientLevel = level;
  }

  float threshold = ambientLevel * STEP_THRESHOLD_MULTIPLIER;

  if (threshold < NOISE_FLOOR * 3.0f) {
    threshold = NOISE_FLOOR * 3.0f;
  }

  // Update ambient when not stepping
  if (level < threshold) {
    ambientLevel =
      ambientLevel * AMBIENT_ALPHA +
      level * (1.0f - AMBIENT_ALPHA);
  }

  // Detect step
  if (
      level > threshold &&
      (now - lastStepTime) > MIN_STEP_GAP_MS
     ) {

    stepDetected = true;

    previousStepTime = lastStepTime;
    lastStepTime = now;

    if (previousStepTime > 0) {

      unsigned long interval =
        lastStepTime - previousStepTime;

      if (interval > 0) {
        bpm = 60000 / interval;
      }
    }
  }

  if ((now - lastStepTime) > BPM_TIMEOUT_MS) {
    bpm = 0;
  }
}

// =====================================================

void setup() {

  Serial.begin(115200);

  delay(2000);

  Serial.println("INMP441 Step Detection Ready");

  setupI2S();
}

// =====================================================

void loop() {

  currentLevel = readMicLevel();

  updateStepDetection(currentLevel);

  if (stepDetected) {

    Serial.print("STEP");

    Serial.print(" | Current: ");
    Serial.print(currentLevel, 1);

    Serial.print(" | Ambient: ");
    Serial.print(ambientLevel, 1);

    Serial.print(" | BPM: ");
    Serial.println(bpm);
  }
}