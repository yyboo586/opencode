package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func doRequest(t *testing.T, out *bytes.Buffer, method, path, body string) *http.Response {
	t.Helper()

	srv := httptest.NewServer(newMux(out, "dev-edge-001"))
	t.Cleanup(srv.Close)

	req, err := http.NewRequest(method, srv.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do request: %v", err)
	}
	t.Cleanup(func() { _ = resp.Body.Close() })
	return resp
}

func decodeJSON(t *testing.T, resp *http.Response) map[string]any {
	t.Helper()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	var got map[string]any
	if err := json.Unmarshal(raw, &got); err != nil {
		t.Fatalf("unmarshal body %q: %v", raw, err)
	}
	return got
}

func TestMux_Endpoints(t *testing.T) {
	cases := []struct {
		name       string
		method     string
		path       string
		body       string
		wantStatus int
		check      func(t *testing.T, resp *http.Response)
	}{
		{
			"device serial returns code 200 and device id",
			http.MethodGet, "/device/serial", "", http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				got := decodeJSON(t, resp)
				if got["code"] != float64(200) || got["msg"] != "ok" || got["data"] != "dev-edge-001" {
					t.Errorf("body = %v; want code=200 msg=ok data=dev-edge-001", got)
				}
			},
		},
		{
			"server ready accepts report and returns code 200",
			http.MethodPost, "/server/ready", `{"edge":"dev-edge-001"}`, http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				got := decodeJSON(t, resp)
				if got["code"] != float64(200) || got["msg"] != "ok" {
					t.Errorf("body = %v; want code=200 msg=ok", got)
				}
			},
		},
		{
			"license query returns empty list",
			http.MethodPost, "/api/device/license", `["dev001"]`, http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				raw, _ := io.ReadAll(resp.Body)
				if strings.TrimSpace(string(raw)) != "[]" {
					t.Errorf("body = %q; want []", string(raw))
				}
			},
		},
		{
			"device alert query returns empty list",
			http.MethodPost, "/api/device/alert", `["dev001"]`, http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				raw, _ := io.ReadAll(resp.Body)
				if strings.TrimSpace(string(raw)) != "[]" {
					t.Errorf("body = %q; want []", string(raw))
				}
			},
		},
		{
			"visualdevice query returns empty list",
			http.MethodPost, "/api/query/visualdevice", `["dev001"]`, http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				raw, _ := io.ReadAll(resp.Body)
				if strings.TrimSpace(string(raw)) != "[]" {
					t.Errorf("body = %q; want []", string(raw))
				}
			},
		},
		{
			"ping returns pong",
			http.MethodGet, "/ping", "", http.StatusOK,
			func(t *testing.T, resp *http.Response) {
				got := decodeJSON(t, resp)
				if got["code"] != float64(200) || got["msg"] != "pong" {
					t.Errorf("body = %v; want code=200 msg=pong", got)
				}
			},
		},
		{
			"wrong method returns 405",
			http.MethodGet, "/server/ready", "", http.StatusMethodNotAllowed,
			func(t *testing.T, resp *http.Response) {},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			resp := doRequest(t, &out, tc.method, tc.path, tc.body)

			if resp.StatusCode != tc.wantStatus {
				t.Errorf("status = %d; want %d", resp.StatusCode, tc.wantStatus)
			}
			if ct := resp.Header.Get("Content-Type"); tc.wantStatus == http.StatusOK && !strings.Contains(ct, "application/json") {
				t.Errorf("Content-Type = %q; want application/json", ct)
			}
			tc.check(t, resp)
		})
	}
}

func TestMux_LogsRequestsWithBody(t *testing.T) {
	var out bytes.Buffer
	resp := doRequest(t, &out, http.MethodPost, "/server/ready", `{"edge":"dev-edge-001"}`)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d; want 200", resp.StatusCode)
	}

	logged := out.String()
	for _, want := range []string{"POST /server/ready", `{"edge":"dev-edge-001"}`} {
		if !strings.Contains(logged, want) {
			t.Errorf("log %q does not contain %q", logged, want)
		}
	}
}
