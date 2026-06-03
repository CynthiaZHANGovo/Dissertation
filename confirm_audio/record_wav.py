import serial
import wave
import time

# ===== Change this =====
PORT = "COM5"         
# =======================

BAUD_RATE = 921600
SAMPLE_RATE = 16000
RECORD_SECONDS = 10
OUTPUT_FILE = "inmp441_recording.wav"

ser = serial.Serial(PORT, BAUD_RATE, timeout=1)
time.sleep(2)

print("Recording...")
audio_data = bytearray()

bytes_needed = SAMPLE_RATE * RECORD_SECONDS * 2  # int16 = 2 bytes

while len(audio_data) < bytes_needed:
    chunk = ser.read(bytes_needed - len(audio_data))
    audio_data.extend(chunk)

ser.close()

with wave.open(OUTPUT_FILE, "wb") as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(SAMPLE_RATE)
    wav_file.writeframes(audio_data)

print(f"Saved: {OUTPUT_FILE}")