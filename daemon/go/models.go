package main

type statsResponse struct {
	CPUUsage       float64 `json:"cpu_usage"`
	RAMUsage       float64 `json:"ram_usage"`
	CPUTemp        float64 `json:"cpu_temp"`
	BatteryPercent float64 `json:"battery_percent"`
	IsPlugged      bool    `json:"is_plugged"`
	Timestamp      float64 `json:"timestamp"`
}

type notificationPayload struct {
	PackageName string `json:"package_name"`
	Title       string `json:"title"`
	Text        string `json:"text"`
	PostedAt    any    `json:"posted_at"`
}

type lidInhibitPayload struct {
	Enabled bool `json:"enabled"`
}
