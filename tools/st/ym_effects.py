#!/usr/bin/env python3
"""YM2149 versions of the game's sound effects, for an Atari ST (no DMA
sound).

Each PCM_DAT/*.sam (signed 8-bit mono, 12517 Hz; the Falcon port's
conversions of the X68000 game's 15.6 kHz ADPCM effects) is cut into 20 ms
frames, one per 50 Hz VBL, and played on the three YM channels at once: A
a tone, C a second tone, B noise. Per frame:

- how tonal the frame is (its spectral flatness: low for tones, high for
  noise) splits its loudness (RMS, smoothed over its neighbours) between
  tones and noise, each a YM volume (3 dB steps; the loudest frames of all
  the effects at 15);
- the strongest spectral peak (100 Hz-4 kHz), or a strong one an octave or
  a twelfth below it (the fundamental), is the first tone; the strongest
  peak that is not one of its harmonics, if strong enough, the second (a
  chord); each kept while it stays within a few percent (less warble), and
  the tones' share split by their peaks;
- the spectral centroid gives the noise period (the YM's noise is white up
  to about half its clock).

The frames go into PCM_DAT\SZ2_YM.BIN, which only an ST loads (an STE
loads the samples instead): 'CRSY', the number of effects (word), the
frame size (word), per effect (YM_ENTRY_SIZE bytes) its sample's file name
(12 bytes, upper case, NUL padded), its frames' offset in the file (long)
and their number (word, then a padding word); then the frames, per 50 Hz
VBL: the first tone's volume (channel A: bits 0-3) and the noise's
(channel B: bits 4-7); the second tone's volume (channel C); the noise
period; a padding byte; the two tone periods (words). Big-endian.
sources/st/audio.s plays them one effect at a time, as the game does.

With --preview DIR, WAV files of each effect as sampled and as a YM2149
plays the frames (rendered here: tone squares, the 17-bit noise register,
3 dB volume steps), and ALL.wav with every effect, sampled then YM, in
turn.

usage:
    ym_effects.py [--pcm binaries/atari/PCM_DAT]
                  [-o binaries/st/PCM_DAT/SZ2_YM.BIN] [--preview DIR]
"""

import argparse
import glob
import os
import struct
import sys
import wave

import numpy as np

SAMPLE_RATE = 12517
FRAMES_PER_SECOND = 50
FRAME = SAMPLE_RATE / FRAMES_PER_SECOND  # 250.34 samples
YM_CLOCK = 2000000
TONE_UNIT = YM_CLOCK / 16  # Tone and noise frequencies: 125000 / period.
PREVIEW_RATE = 44100

LOWEST_PITCH = 100.0  # Hz
HIGHEST_PITCH = 4000.0
TONAL_FLATNESS = 0.05  # At or below: all tone.
NOISY_FLATNESS = 0.30  # At or above: all noise.
PITCH_HOLD = 0.04  # A new peak within 4 % keeps the tone (less warble).
SUBHARMONIC = 0.25  # A peak at f/2 or f/3 this strong (-6 dB): the fundamental.
SECOND_TONE = 0.125  # A second tone at least this strong (-9 dB).
HARMONIC_MARGIN = 0.06  # Within 6 % of a harmonic: part of the first tone.
NOISE_BRIGHTNESS = 2.5  # Noise clock = this * the spectral centroid.
VOLUME_STEP_DB = 3.0
FFT_SIZE = 4096


def read_sam(path):
    data = np.frombuffer(open(path, "rb").read(), dtype=np.int8)
    return data.astype(np.float64) / 128.0


def frame_count(samples):
    return int(np.ceil(len(samples) / FRAME))


def peak_power(spectrum, frequency):
    """The strongest power within 3 % of frequency."""
    low = int(frequency * 0.97 * FFT_SIZE / SAMPLE_RATE)
    high = int(np.ceil(frequency * 1.03 * FFT_SIZE / SAMPLE_RATE)) + 1
    if low < 1 or high >= len(spectrum):
        return 0.0
    return float(spectrum[low:high].max())


def interpolated(spectrum, k):
    """Bin k's peak frequency, by parabolic interpolation."""
    if 0 < k < len(spectrum) - 1:
        a, b, c = np.log(spectrum[k - 1:k + 2])
        shift = 0.5 * (a - c) / (a - 2 * b + c) if a - 2 * b + c else 0.0
    else:
        shift = 0.0
    return (k + shift) * SAMPLE_RATE / FFT_SIZE


def analyse(samples):
    """Per frame: power, flatness, (first tone Hz, its peak power), (second
    tone Hz or 0, its peak power), centroid Hz."""
    result = []
    frequencies = np.fft.rfftfreq(FFT_SIZE, 1.0 / SAMPLE_RATE)
    band = (frequencies >= LOWEST_PITCH) & (frequencies <= HIGHEST_PITCH)
    for i in range(frame_count(samples)):
        start = int(round(i * FRAME))
        frame = samples[start:int(round((i + 1) * FRAME))]
        power = float(np.mean(frame ** 2)) if len(frame) else 0.0

        # Two frames' window for the spectrum: room for low notes.
        window = samples[start:start + int(2 * FRAME)]
        if len(window) < 64 or power == 0:
            result.append((power, 1.0, (0.0, 0.0), (0.0, 0.0), 0.0))
            continue
        x = (window - window.mean()) * np.hanning(len(window))
        spectrum = np.abs(np.fft.rfft(x, FFT_SIZE)) ** 2 + 1e-12
        flatness = float(np.exp(np.mean(np.log(spectrum[1:]))) / np.mean(spectrum[1:]))
        centroid = float((frequencies * spectrum).sum() / spectrum.sum())

        in_band = np.where(band, spectrum, 0)
        k = int(np.argmax(in_band))
        first = interpolated(spectrum, k)
        first_power = float(spectrum[k])
        for divisor in (2, 3):  # The fundamental, if strong enough.
            below = first / divisor
            if below >= LOWEST_PITCH and peak_power(spectrum, below) >= SUBHARMONIC * first_power:
                first = below
                first_power = peak_power(spectrum, below)
                break

        if first < LOWEST_PITCH:  # Nothing in the band.
            result.append((power, flatness, (0.0, 0.0), (0.0, 0.0), centroid))
            continue

        # The second tone: the strongest peak away from the first's harmonics.
        mask = in_band.copy()
        harmonic = first
        while harmonic <= HIGHEST_PITCH * 1.1:
            low = int(harmonic * (1 - HARMONIC_MARGIN) * FFT_SIZE / SAMPLE_RATE)
            high = int(harmonic * (1 + HARMONIC_MARGIN) * FFT_SIZE / SAMPLE_RATE) + 1
            mask[max(0, low):high] = 0
            harmonic += first
        k2 = int(np.argmax(mask))
        second, second_power = 0.0, 0.0
        if mask[k2] >= SECOND_TONE * float(spectrum[k]):
            second, second_power = interpolated(spectrum, k2), float(spectrum[k2])

        result.append((power, flatness, (first, first_power), (second, second_power), centroid))
    return result


def ym_volume_of(power, reference):
    if power <= 0:
        return 0
    level = 15 + int(round(10 * np.log10(power / reference) / VOLUME_STEP_DB))
    return max(0, min(15, level))


def held(pitch, new):
    """The pitch kept, or the new one if it moved by more than PITCH_HOLD."""
    if new <= 0:
        return pitch
    if pitch and abs(new - pitch) <= PITCH_HOLD * pitch:
        return pitch
    return new


def period_of(pitch):
    return max(1, min(4095, int(round(TONE_UNIT / pitch)))) if pitch else 0


def ym_frames(analysis, reference):
    """Per frame: tone A volume, noise volume, tone C volume, noise period,
    tone A period, tone C period."""
    powers = np.array([a[0] for a in analysis])
    # Loudness smoothed over the neighbours (power: 1/4, 1/2, 1/4).
    padded = np.concatenate([[0.0], powers, [0.0]])
    smooth = 0.25 * padded[:-2] + 0.5 * padded[1:-1] + 0.25 * padded[2:]

    frames = []
    pitch_a = pitch_c = 0.0
    period_a = period_c = 0
    noise_period = 16
    for i, (power, flatness, (first, first_power), (second, second_power),
            centroid) in enumerate(analysis):
        tonal = (NOISY_FLATNESS - flatness) / (NOISY_FLATNESS - TONAL_FLATNESS)
        tonal = max(0.0, min(1.0, tonal))
        share_c = second_power / (first_power + second_power) if second else 0.0
        volume_a = ym_volume_of(smooth[i] * tonal * (1 - share_c), reference)
        volume_c = ym_volume_of(smooth[i] * tonal * share_c, reference)
        noise_volume = ym_volume_of(smooth[i] * (1 - tonal), reference)
        if volume_a:
            pitch_a = held(pitch_a, first)
            period_a = period_of(pitch_a)
        if volume_c:
            pitch_c = held(pitch_c, second)
            period_c = period_of(pitch_c)
        if noise_volume and centroid > 0:
            noise_period = max(1, min(31, int(round(TONE_UNIT / (NOISE_BRIGHTNESS * centroid)))))
        frames.append([volume_a, noise_volume, volume_c, noise_period, period_a, period_c])

    while frames and not (frames[-1][0] or frames[-1][1] or frames[-1][2]):
        frames.pop()  # Trailing silence.
    return frames


# --- The file -------------------------------------------------------------------

YM_ENTRY_SIZE = 20
YM_FRAME_SIZE = 8


def write_effects(path, effects):
    header = struct.pack(">4sHH", b"CRSY", len(effects), YM_FRAME_SIZE)
    offset = len(header) + YM_ENTRY_SIZE * len(effects)
    directory = b""
    frames_data = b""
    for name, frames in effects:
        directory += struct.pack(">12sLHH", name.encode("ascii")[:12], offset + len(frames_data),
                                 len(frames), 0)
        for volume_a, noise_volume, volume_c, noise_period, period_a, period_c in frames:
            frames_data += struct.pack(">BBBBHH", volume_a | (noise_volume << 4), volume_c,
                                       noise_period, 0, period_a, period_c)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    open(path, "wb").write(header + directory + frames_data)
    return len(header + directory + frames_data)


# --- Previews -------------------------------------------------------------------

def ym_volume(level):
    return 0.0 if level == 0 else 2.0 ** ((level - 15) / 2.0)


def render(frames, slow=False):
    """The frames as a YM2149 plays them (A and C tones, B noise), at
    PREVIEW_RATE."""
    per_frame = int(PREVIEW_RATE / FRAMES_PER_SECOND * (1.5 if slow else 1.0))
    out = np.zeros(per_frame * len(frames))
    phase_a = phase_c = 0.0
    noise_phase = 0.0
    lfsr = 1
    noise_bit = 1
    for i, (volume_a, noise_volume, volume_c, noise_period, period_a,
            period_c) in enumerate(frames):
        if slow:
            period_a = min(4095, period_a * 3 // 2)
            period_c = min(4095, period_c * 3 // 2)
            noise_period = min(31, noise_period * 3 // 2)
        step_a = TONE_UNIT / max(1, period_a) / PREVIEW_RATE
        step_c = TONE_UNIT / max(1, period_c) / PREVIEW_RATE
        noise_step = TONE_UNIT / max(1, noise_period) / PREVIEW_RATE
        amplitude_a = ym_volume(volume_a)
        amplitude_c = ym_volume(volume_c)
        noise_amplitude = ym_volume(noise_volume)
        block = np.empty(per_frame)
        for j in range(per_frame):
            phase_a = (phase_a + step_a) % 1.0
            phase_c = (phase_c + step_c) % 1.0
            noise_phase += noise_step
            while noise_phase >= 1.0:
                noise_phase -= 1.0
                bit = (lfsr ^ (lfsr >> 3)) & 1  # x^17 + x^14 + 1
                lfsr = (lfsr >> 1) | (bit << 16)
                noise_bit = lfsr & 1
            block[j] = (amplitude_a if phase_a < 0.5 else 0.0) + \
                       (amplitude_c if phase_c < 0.5 else 0.0) + \
                       (noise_amplitude if noise_bit else 0.0)
        out[i * per_frame:(i + 1) * per_frame] = block
    # The YM's output has a DC offset: a gentle high-pass, as an amplifier.
    if len(out):
        out = out - np.convolve(out, np.ones(441) / 441, mode="same")
    return out


def resampled(samples):
    t = np.arange(int(len(samples) * PREVIEW_RATE / SAMPLE_RATE)) / PREVIEW_RATE
    return np.interp(t, np.arange(len(samples)) / SAMPLE_RATE, samples)


def write_wav(path, signal):
    peak = max(1e-9, np.max(np.abs(signal)))
    data = (np.clip(signal / max(peak, 1.0), -1, 1) * 30000).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(PREVIEW_RATE)
        w.writeframes(data.tobytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pcm", default="binaries/atari/PCM_DAT")
    parser.add_argument("-o", "--output", default="binaries/st/PCM_DAT/SZ2_YM.BIN")
    parser.add_argument("--preview")
    args = parser.parse_args()

    paths = sorted(glob.glob(os.path.join(args.pcm, "*.sam")))
    if not paths:
        raise SystemExit("%s: no .sam files" % args.pcm)

    sounds = []
    for path in paths:
        raw = open(path, "rb").read()
        samples = read_sam(path)
        sounds.append((os.path.basename(path).upper(), raw, samples, analyse(samples)))

    # The loudest frames of all the effects: volume 15.
    all_power = np.array([a[0] for _, _, _, analysis in sounds for a in analysis])
    reference = float(np.percentile(all_power[all_power > 0], 99.5))

    effects = []
    for name, raw, samples, analysis in sounds:
        frames = ym_frames(analysis, reference)
        effects.append((name, frames))
        chords = sum(1 for f in frames if f[2])
        tones = sum(1 for f in frames if f[0] and not f[1])
        both = sum(1 for f in frames if f[0] and f[1])
        noises = sum(1 for f in frames if f[1] and not f[0])
        print("%-14s %6d bytes %3d frames: tone %3d, both %3d, noise %3d, chord %3d, loudest %2d"
              % (name, len(raw), len(frames), tones, both, noises, chords,
                 max([max(f[0], f[1], f[2]) for f in frames] or [0])))

    size = write_effects(args.output, effects)
    print("wrote %s (%d effects, %d frames, %d bytes)" % (args.output, len(effects),
                                                           sum(len(e[1]) for e in effects), size))

    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        everything = []
        gap = np.zeros(int(0.3 * PREVIEW_RATE))
        index = []
        position = 0.0
        for (name, raw, samples, _), (_, frames) in zip(sounds, effects):
            original = resampled(samples)
            ym = render(frames)
            stem = os.path.join(args.preview, os.path.splitext(name)[0])
            write_wav(stem + "_SAM.wav", original)
            write_wav(stem + "_YM.wav", ym)
            index.append("%7.2f s  %s: sampled, then YM at %.2f s"
                         % (position, name, position + (len(original) + len(gap)) / PREVIEW_RATE))
            for part in (original, gap, ym * 0.5, gap, gap):
                everything.append(part)
                position += len(part) / PREVIEW_RATE
        write_wav(os.path.join(args.preview, "ALL.wav"), np.concatenate(everything))
        open(os.path.join(args.preview, "ALL.txt"), "w").write("\n".join(index) + "\n")
        print("previews in %s (ALL.wav: every effect sampled then YM; ALL.txt: where)"
              % args.preview)


if __name__ == "__main__":
    sys.exit(main())
