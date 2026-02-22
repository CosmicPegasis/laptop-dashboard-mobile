package main

import (
	"os"
	"path/filepath"
)

const (
	port = "8081"
)

var (
	uploadDir      = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_transfers")
	shareDir       = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_share")
	lidInhibitFile = "lid_inhibit.state"
)
