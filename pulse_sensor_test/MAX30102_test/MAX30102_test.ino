#include <Wire.h>
#include "MAX30105.h"

MAX30105 particleSensor;

void setup()
{
  Serial.begin(115200);
  while (!Serial);

  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD))
  {
    Serial.println("MAX30102 not found");
    while (1);
  }

  Serial.println("Place finger on sensor");
}

void loop()
{
  long irValue = particleSensor.getIR();

  Serial.println(irValue);

  delay(20);
}