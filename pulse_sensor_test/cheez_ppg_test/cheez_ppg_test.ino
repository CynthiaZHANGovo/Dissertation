const int PPG_PIN = A0;

const int SAMPLE_DELAY = 20; // 50Hz
const int BUF_SIZE = 12;

int buf[BUF_SIZE];
int idx = 0;

int lastFiltered = 0;
bool wasRising = false;

unsigned long lastBeatTime = 0;

int bpmHistory[5];
int bpmIdx = 0;
int bpmCount = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial);

  for (int i = 0; i < BUF_SIZE; i++) {
    buf[i] = analogRead(PPG_PIN);
  }

  Serial.println("Conservative PPG BPM started");
}

void loop() {
  int raw = analogRead(PPG_PIN);

  if (raw < 300 || raw > 950) {
    Serial.print("Bad signal raw=");
    Serial.println(raw);
    delay(SAMPLE_DELAY);
    return;
  }

  buf[idx] = raw;
  idx = (idx + 1) % BUF_SIZE;

  long sum = 0;
  for (int i = 0; i < BUF_SIZE; i++) sum += buf[i];
  int filtered = sum / BUF_SIZE;

  int diff = filtered - lastFiltered;

  // 太小的抖动不算心跳
  if (abs(diff) < 3) {
    delay(SAMPLE_DELAY);
    return;
  }

  bool rising = diff > 0;

  if (wasRising && !rising) {
    unsigned long now = millis();
    unsigned long interval = now - lastBeatTime;

    // 限制到比较合理的心率范围：50–120 BPM
    if (interval > 500 && interval < 1200) {
      int newBpm = 60000 / interval;

      // 如果和上一次平均差太多，先忽略
      int avgBpm = getAverageBpm();
      if (avgBpm == 0 || abs(newBpm - avgBpm) < 25) {
        bpmHistory[bpmIdx] = newBpm;
        bpmIdx = (bpmIdx + 1) % 5;
        if (bpmCount < 5) bpmCount++;

        Serial.print("Raw: ");
        Serial.print(raw);
        Serial.print(" Filtered: ");
        Serial.print(filtered);
        Serial.print(" BPM: ");
        Serial.println(getAverageBpm());
      }
    }

    lastBeatTime = now;
  }

  wasRising = rising;
  lastFiltered = filtered;

  delay(SAMPLE_DELAY);
}

int getAverageBpm() {
  if (bpmCount == 0) return 0;

  int sum = 0;
  for (int i = 0; i < bpmCount; i++) {
    sum += bpmHistory[i];
  }
  return sum / bpmCount;
}