// Pulse Sensor + Arduino Nano 33 BLE
// Wiring:
// Red    -> 3.3V
// Black  -> GND
// Purple -> A0

const int PULSE_PIN = A0;

// ===== 可调参数 =====
int THRESHOLD = 550;          // 心跳峰值阈值：如果一直没 BPM，调低；误判太多，调高
int SAMPLE_DELAY = 2;         // 采样间隔 ms：建议 2，不要太大
int MIN_BPM = 45;             // 最低合理 BPM
int MAX_BPM = 180;            // 最高合理 BPM
int SMOOTHING = 8;            // 平滑程度：越大越稳，但反应越慢
// ====================

int signalValue = 0;
float smoothValue = 0;

bool wasAboveThreshold = false;

unsigned long lastBeatTime = 0;
int bpm = 0;

void setup() {
  Serial.begin(115200);
  delay(1000);

  smoothValue = analogRead(PULSE_PIN);

  Serial.println("Pulse sensor started");
}

void loop() {
  signalValue = analogRead(PULSE_PIN);

  // 简单平滑滤波
  smoothValue = smoothValue + (signalValue - smoothValue) / SMOOTHING;

  bool isAboveThreshold = smoothValue > THRESHOLD;

  // 从低于阈值变成高于阈值，认为检测到一次心跳
  if (isAboveThreshold && !wasAboveThreshold) {
    unsigned long now = millis();
    unsigned long interval = now - lastBeatTime;

    if (lastBeatTime > 0) {
      int currentBpm = 60000 / interval;

      if (currentBpm >= MIN_BPM && currentBpm <= MAX_BPM) {
        bpm = currentBpm;

        Serial.print("bpm:");
        Serial.println(bpm);
      }
    }

    lastBeatTime = now;
  }

  wasAboveThreshold = isAboveThreshold;

  delay(SAMPLE_DELAY);
}