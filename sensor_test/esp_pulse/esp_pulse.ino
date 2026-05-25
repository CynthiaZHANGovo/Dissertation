const int pulsePin = A0;

int threshold = 2200;   // 这个值可能要根据你的Raw波形调
bool wasAbove = false;

unsigned long lastBeatTime = 0;
int bpm = 0;

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("Pulse BPM test");
}

void loop() {
  int value = analogRead(pulsePin);

  bool isAbove = value > threshold;

  if (isAbove && !wasAbove) {
    unsigned long now = millis();

    if (now - lastBeatTime > 300) {
      bpm = 60000 / (now - lastBeatTime);
      lastBeatTime = now;
    }
  }

  wasAbove = isAbove;

  Serial.print("Raw:");
  Serial.print(value);
  Serial.print(",");
  Serial.print("Threshold:");
  Serial.print(threshold);
  Serial.print(",");
  Serial.print("BPM:");
  Serial.println(bpm);

  delay(20);
}