package main

import (
	"context"
	"log/slog"
	"os"

	"gopkg.in/natefinch/lumberjack.v2"
)

const (
	logFile    = "stats_daemon.log"
	maxLogMB   = 10
	maxBackups = 5
)

func setupLogging() {
	rotatingFile := &lumberjack.Logger{
		Filename:   logFile,
		MaxSize:    maxLogMB,
		MaxBackups: maxBackups,
	}
	fileHandler := slog.NewTextHandler(rotatingFile, nil)
	stdoutHandler := slog.NewTextHandler(os.Stdout, nil)
	slog.SetDefault(slog.New(&multiHandler{handlers: []slog.Handler{fileHandler, stdoutHandler}}))
}

type multiHandler struct {
	handlers []slog.Handler
}

func (m *multiHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, h := range m.handlers {
		if h.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (m *multiHandler) Handle(ctx context.Context, r slog.Record) error {
	for _, h := range m.handlers {
		_ = h.Handle(ctx, r.Clone())
	}
	return nil
}

func (m *multiHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	handlers := make([]slog.Handler, len(m.handlers))
	for i, h := range m.handlers {
		handlers[i] = h.WithAttrs(attrs)
	}
	return &multiHandler{handlers: handlers}
}

func (m *multiHandler) WithGroup(name string) slog.Handler {
	handlers := make([]slog.Handler, len(m.handlers))
	for i, h := range m.handlers {
		handlers[i] = h.WithGroup(name)
	}
	return &multiHandler{handlers: handlers}
}
