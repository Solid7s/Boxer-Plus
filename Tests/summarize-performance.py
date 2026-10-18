#!/usr/bin/env python3
"""Summarize probe logs after 20 seconds of warmup; FPS means presentations."""
import json
import statistics
import sys
from pathlib import Path


def summarize(path):
    samples = []
    for line in Path(path).read_text(errors="replace").splitlines():
        if line.startswith('{"'):
            value = json.loads(line)
            if "elapsed" in value and value["elapsed"] >= 20:
                samples.append(value)
    if len(samples) < 2:
        return {"log": str(path), "error": "insufficient samples"}
    first, last = samples[0], samples[-1]
    duration = last["elapsed"] - first["elapsed"]
    cpu_seconds = sum(b["cpuPercent"] / 100 * (b["elapsed"] - a["elapsed"])
                      for a, b in zip(samples, samples[1:]))
    result = {"log": str(path), "seconds": duration,
              "meanCPUPercent": cpu_seconds / duration * 100,
              "meanCycles": statistics.mean(s["cycles"] for s in samples),
              "gpu": last.get("gpu"), "limit": last.get("cycleLimit"),
              "automatic": last["auto"], "samples": len(samples)}
    for source, target in (("draws", "presentationsPerSecond"),
                           ("eventPumps", "eventPumpsPerSecond"),
                           ("voluntarySwitches", "voluntarySwitchesPerSecond"),
                           ("involuntarySwitches", "involuntarySwitchesPerSecond"),
                           ("audioBytes", "audioBytesPerSecond")):
        if source in first and source in last:
            result[target] = (last[source] - first[source]) / duration
    if "GPUTime" in last:
        completed = last["completedFrames"] - first["completedFrames"]
        draws = last["draws"] - first["draws"]
        result["gpuMillisecondsPerFrame"] = 1000 * (last["GPUTime"] - first["GPUTime"]) / max(1, completed)
        result["drawableWaitMillisecondsPerFrame"] = 1000 * (last["drawableWaitTime"] - first["drawableWaitTime"]) / max(1, draws)
        result["GPUFailures"] = last["GPUFailures"]
    result["passed"] = "PASS: game probe completed" in Path(path).read_text(errors="replace")
    for field in ("audioEmptySamples", "audioNonSilentSamples", "audioBytes"):
        if field in first and field in last:
            result[field] = last[field] - first[field]
    if "audioQueueBytes" in last:
        result["audioQueueBytesRange"] = [min(s["audioQueueBytes"] for s in samples), max(s["audioQueueBytes"] for s in samples)]
        result["audioDeviceStatus"] = last["audioDeviceStatus"]
    return result


if __name__ == "__main__":
    print(json.dumps([summarize(path) for path in sys.argv[1:]], indent=2))
