package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
)

type mockHTTP struct {
	out      io.Writer
	deviceID string
}

func (h *mockHTTP) log(r *http.Request, body []byte) {
	line := fmt.Sprintf("[mock-http] %s %s", r.Method, r.URL.Path)
	if len(body) > 0 {
		line += " body=" + string(body)
	}
	fmt.Fprintln(h.out, line)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(b)
}

func newMux(out io.Writer, deviceID string) *http.ServeMux {
	h := &mockHTTP{out: out, deviceID: deviceID}
	mux := http.NewServeMux()

	mux.HandleFunc("GET /device/serial", func(w http.ResponseWriter, r *http.Request) {
		h.log(r, nil)
		writeJSON(w, http.StatusOK, map[string]any{"code": 200, "msg": "ok", "data": h.deviceID})
	})

	mux.HandleFunc("POST /server/ready", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		h.log(r, body)
		writeJSON(w, http.StatusOK, map[string]any{"code": 200, "msg": "ok"})
	})

	emptyList := func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		h.log(r, body)
		writeJSON(w, http.StatusOK, []any{})
	}
	mux.HandleFunc("POST /api/device/license", emptyList)
	mux.HandleFunc("POST /api/device/alert", emptyList)
	mux.HandleFunc("POST /api/query/visualdevice", emptyList)

	mux.HandleFunc("GET /ping", func(w http.ResponseWriter, r *http.Request) {
		h.log(r, nil)
		writeJSON(w, http.StatusOK, map[string]any{"code": 200, "msg": "pong"})
	})

	return mux
}

func main() {
	addr := flag.String("addr", ":9999", "HTTP listen address")
	deviceID := flag.String("device-id", "dev-edge-001", "device id returned by /device/serial")
	flag.Parse()

	fmt.Printf("[mock-http] listening on %s\n", *addr)
	if err := http.ListenAndServe(*addr, newMux(os.Stdout, *deviceID)); err != nil {
		fmt.Fprintf(os.Stderr, "serve: %v\n", err)
		os.Exit(1)
	}
}
