const int SENSOR_PIN = A0;

int lastValue = 0;

unsigned long lastStepTime = 0;
int stepBPM = 0;

// 差值阈值
const int DIFF_THRESHOLD = 60;

// 防止重复检测
const int STEP_COOLDOWN = 250;

void setup() {
  Serial.begin(115200);
  while (!Serial);

  lastValue = analogRead(SENSOR_PIN);

  Serial.println("Step BPM detector started");
}

void loop() {

  int currentValue = analogRead(SENSOR_PIN);

  int diff = abs(currentValue - lastValue);

  unsigned long now = millis();

  // 检测突然变化
  if (diff > DIFF_THRESHOLD &&
      now - lastStepTime > STEP_COOLDOWN) {

    unsigned long interval = now - lastStepTime;

    // 合理步频范围
    if (interval > 250 && interval < 2000) {

      stepBPM = 60000 / interval;

      Serial.print("Value: ");
      Serial.print(currentValue);

      Serial.print(" Diff: ");
      Serial.print(diff);

      Serial.print(" Step BPM: ");
      Serial.println(stepBPM);
    }

    lastStepTime = now;
  }

  lastValue = currentValue;

  delay(10);
}