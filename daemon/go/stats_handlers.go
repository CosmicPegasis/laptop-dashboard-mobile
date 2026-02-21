package main

import (
	"log/slog"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
)

// coretemp → cpu_thermal → first available sensor → 0
func getCPUTemp() float64 {
	temps, err := host.SensorsTemperatures()
	if err != nil || len(temps) == 0 {
		return 0
	}

	byKey := make(map[string][]host.TemperatureStat)
	for _, t := range temps {
		byKey[t.SensorKey] = append(byKey[t.SensorKey], t)
	}

	for _, key := range []string{"coretemp", "cpu_thermal"} {
		if entries, ok := byKey[key]; ok && len(entries) > 0 {
			return entries[0].Temperature
		}
	}
	return temps[0].Temperature
}

// getBattery reads battery info via upower CLI (mirrors Python's psutil fallback).
func getBattery() (percent float64, plugged bool) {
	devicesOut, err := exec.Command("upower", "-e").Output()
	if err != nil {
		return 0, false
	}
	for _, dev := range strings.Split(strings.TrimSpace(string(devicesOut)), "\n") {
		if !strings.Contains(dev, "battery") {
			continue
		}
		infoOut, err := exec.Command("upower", "-i", dev).Output()
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(infoOut), "\n") {
			if strings.Contains(line, "percentage:") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					val := strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(parts[1]), "%"))
					if f, err := strconv.ParseFloat(val, 64); err == nil {
						percent = f
					}
				}
			}
			if strings.Contains(line, "state:") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					state := strings.ToLower(strings.TrimSpace(parts[1]))
					plugged = state == "charging" || state == "fully-charged"
				}
			}
		}
		return percent, plugged
	}
	return 0, false
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	clientIP := r.RemoteAddr

	cpuPercents, err := cpu.Percent(0, false)
	cpuUsage := 0.0
	if err == nil && len(cpuPercents) > 0 {
		cpuUsage = cpuPercents[0]
	}

	vmStat, err := mem.VirtualMemory()
	ramUsage := 0.0
	if err == nil {
		ramUsage = vmStat.UsedPercent
	}

	cpuTemp := getCPUTemp()
	batteryPercent, isPlugged := getBattery()

	resp := statsResponse{
		CPUUsage:       cpuUsage,
		RAMUsage:       ramUsage,
		CPUTemp:        cpuTemp,
		BatteryPercent: batteryPercent,
		IsPlugged:      isPlugged,
		Timestamp:      float64(time.Now().UnixMilli()) / 1000.0,
	}

	writeJSON(w, http.StatusOK, resp)
	slog.Info("Served stats", "client", clientIP)
}
