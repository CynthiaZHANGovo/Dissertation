#include <Arduino.h>
#include "driver/i2s.h"

// INMP441 + XIAO ESP32C3
#define I2S_SCK D3
#define I2S_WS  D2
#define I2S_SD  D4

#define SAMPLE_RATE     16000
#define I2S_PORT        I2S_NUM_0
#define BUFFER_SAMPLES  512

int32_t i2sBuffer[BUFFER_SAMPLES];
int16_t serialBuffer[BUFFER_SAMPLES];

void setupI2S() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = SAMPLE_RATE,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 8,
    .dma_buf_len = BUFFER_SAMPLES,
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

void setup() {
  Serial.begin(921600);
  delay(1000);
  setupI2S();
}

void loop() {
  size_t bytesRead = 0;

  i2s_read(
    I2S_PORT,
    (void*)i2sBuffer,
    sizeof(i2sBuffer),
    &bytesRead,
    portMAX_DELAY
  );

  int samplesRead = bytesRead / sizeof(int32_t);

  for (int i = 0; i < samplesRead; i++) {
    int32_t sample = i2sBuffer[i];

    sample = sample >> 14;

    if (sample > 32767) sample = 32767;
    if (sample < -32768) sample = -32768;

    serialBuffer[i] = (int16_t)sample;
  }

  Serial.write((uint8_t*)serialBuffer, samplesRead * sizeof(int16_t));
}