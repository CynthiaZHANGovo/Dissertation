#include <driver/i2s.h>

// ======================================================
// USER SETTINGS
// ======================================================

// ---- I2S Pins ----
#define I2S_WS    4
#define I2S_SCK   5
#define I2S_SD    6

// ---- Audio Settings ----
#define SAMPLE_RATE        16000
#define BUFFER_SIZE        256

// ---- Ambient Noise ----
#define AMBIENT_SMOOTHING  0.95f
// Higher = smoother/slower response
// Lower = faster response

// ---- Step Detection ----
#define STEP_THRESHOLD     800
// Increase if false triggers
// Decrease if steps are missed

#define STEP_COOLDOWN_MS   250
// Minimum time between detected steps

// ---- BPM Settings ----
#define BPM_AVERAGE_COUNT  6
// Number of recent steps used for BPM smoothing

// ======================================================

#define I2S_PORT I2S_NUM_0

float ambientLevel = 0;

unsigned long lastStepTime = 0;

float bpmBuffer[BPM_AVERAGE_COUNT];
int bpmIndex = 0;
bool bpmBufferFilled = false;

// ======================================================

void setup() {

  Serial.begin(115200);
  delay(1000);

  Serial.println("System starting...");

  // I2S configuration
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 4,
    .dma_buf_len = BUFFER_SIZE,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  // Pin configuration
  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  // Start I2S
  i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_PORT, &pin_config);
  i2s_zero_dma_buffer(I2S_PORT);

  Serial.println("Ready.");
}

// ======================================================

void loop() {

  int32_t samples[BUFFER_SIZE];
  size_t bytesRead = 0;

  i2s_read(
    I2S_PORT,
    samples,
    sizeof(samples),
    &bytesRead,
    portMAX_DELAY
  );

  int sampleCount = bytesRead / sizeof(int32_t);

  long sum = 0;

  for (int i = 0; i < sampleCount; i++) {

    int32_t sample = samples[i] >> 14;

    sum += abs(sample);
  }

  // Current audio energy
  float currentLevel = (float)sum / sampleCount;

  // Smooth ambient noise
  ambientLevel =
    (ambientLevel * AMBIENT_SMOOTHING) +
    (currentLevel * (1.0f - AMBIENT_SMOOTHING));

  // ======================================================
  // STEP DETECTION
  // ======================================================

  bool stepDetected = false;

  unsigned long currentTime = millis();

  if (
    currentLevel > ambientLevel + STEP_THRESHOLD &&
    currentTime - lastStepTime > STEP_COOLDOWN_MS
  ) {

    stepDetected = true;

    // Calculate BPM
    if (lastStepTime > 0) {

      float intervalSec =
        (currentTime - lastStepTime) / 1000.0f;

      float bpm = 60.0f / intervalSec;

      bpmBuffer[bpmIndex] = bpm;

      bpmIndex++;

      if (bpmIndex >= BPM_AVERAGE_COUNT) {
        bpmIndex = 0;
        bpmBufferFilled = true;
      }
    }

    lastStepTime = currentTime;
  }

  // ======================================================
  // BPM SMOOTHING
  // ======================================================

  float bpmAverage = 0;

  int count =
    bpmBufferFilled ?
    BPM_AVERAGE_COUNT :
    bpmIndex;

  if (count > 0) {

    for (int i = 0; i < count; i++) {
      bpmAverage += bpmBuffer[i];
    }

    bpmAverage /= count;
  }

  // ======================================================
  // SERIAL OUTPUT
  // ======================================================

  Serial.print("Ambient: ");
  Serial.print((int)ambientLevel);

  Serial.print(" | Current: ");
  Serial.print((int)currentLevel);

  Serial.print(" | Step: ");

  if (stepDetected) {
    Serial.print("YES");
  } else {
    Serial.print("NO");
  }

  Serial.print(" | BPM: ");
  Serial.println((int)bpmAverage);

  delay(30);
}