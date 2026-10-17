"""Moves Hatari's mouse through its --cmd-fifo: "mousemove DX DY" every
PERIOD seconds for DURATION seconds from when the fifo appears (EmuMD's
Hatari has the mousemove event; see tests/st/mouse_test.sh).

    mouse_stream.py FIFO DX DY DURATION [PERIOD (default 0.02)]
"""

import os
import stat
import sys
import time

fifo, dx, dy, duration = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
period = float(sys.argv[5]) if len(sys.argv) > 5 else 0.02

deadline = time.time() + 60
while True:
    try:
        if stat.S_ISFIFO(os.stat(fifo).st_mode):
            break
    except FileNotFoundError:
        pass
    if time.time() > deadline:
        sys.exit(f"{fifo}: no fifo")
    time.sleep(0.01)

start = next_time = time.time()
fd = os.open(fifo, os.O_WRONLY)
line = f"hatari-event mousemove {dx} {dy}\n".encode()
try:
    while time.time() - start < duration:
        os.write(fd, line)
        next_time += period
        time.sleep(max(0, next_time - time.time()))
except BrokenPipeError:  # Hatari has ended.
    pass
os.close(fd)
