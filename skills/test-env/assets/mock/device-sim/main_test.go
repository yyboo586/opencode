package main

import (
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"
)

func TestDataTopic(t *testing.T) {
	cases := []struct {
		name   string
		mode   string
		device string
		want   string
	}{
		{"网关设备", "gateway", "dev001", "v1/gateway/dev001/data"},
		{"网关设备-自定义名", "gateway", "sensor-2", "v1/gateway/sensor-2/data"},
		{"直连设备", "direct", "dev001", "v1/device/dev001/data"},
		{"直连设备-自定义名", "direct", "sensor-2", "v1/device/sensor-2/data"},
		{"模式缺省按网关", "", "dev001", "v1/gateway/dev001/data"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := dataTopic(tc.mode, tc.device); got != tc.want {
				t.Errorf("dataTopic(%q, %q) = %q; want %q", tc.mode, tc.device, got, tc.want)
			}
		})
	}
}

func TestCommandTopics(t *testing.T) {
	cases := []struct {
		name   string
		mode   string
		device string
		want   []string
	}{
		{"网关设备", "gateway", "dev001", []string{"v1/gateway/dev001/attributes", "v1/gateway/dev001/rpc"}},
		{"直连设备", "direct", "dev001", []string{"v1/device/dev001/attributes", "v1/device/dev001/rpc"}},
		{"网关设备-自定义名", "gateway", "sensor-2", []string{"v1/gateway/sensor-2/attributes", "v1/gateway/sensor-2/rpc"}},
		{"模式缺省按网关", "", "dev001", []string{"v1/gateway/dev001/attributes", "v1/gateway/dev001/rpc"}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := commandTopics(tc.mode, tc.device)
			if len(got) != len(tc.want) {
				t.Fatalf("commandTopics(%q, %q) = %v; want %v", tc.mode, tc.device, got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Errorf("commandTopics(%q, %q)[%d] = %q; want %q", tc.mode, tc.device, i, got[i], tc.want[i])
				}
			}
		})
	}
}

func TestBuildReport(t *testing.T) {
	cases := []struct {
		name         string
		seq          int
		ts           int64
		wantTemp     float64
		wantHumidity float64
	}{
		{"首条", 1, 1789357000000, 20.1, 41},
		{"第十条", 10, 1789357000000, 21.0, 50},
		{"第99条", 99, 1789357000000, 29.9, 89},
		{"序号回绕", 100, 1789357000000, 20.0, 40},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			raw := buildReport("dev001", tc.seq, tc.ts)

			var got struct {
				Device     string `json:"device"`
				Seq        int    `json:"seq"`
				Timestamp  int64  `json:"timestamp"`
				Attributes struct {
					Temperature float64 `json:"temperature"`
					Humidity    float64 `json:"humidity"`
				} `json:"attributes"`
			}
			if err := json.Unmarshal(raw, &got); err != nil {
				t.Fatalf("unmarshal report %q: %v", raw, err)
			}

			if got.Device != "dev001" {
				t.Errorf("device = %q; want dev001", got.Device)
			}
			if got.Seq != tc.seq {
				t.Errorf("seq = %d; want %d", got.Seq, tc.seq)
			}
			if got.Timestamp != tc.ts {
				t.Errorf("timestamp = %d; want %d", got.Timestamp, tc.ts)
			}
			if math.Abs(got.Attributes.Temperature-tc.wantTemp) > 1e-9 {
				t.Errorf("temperature = %v; want %v", got.Attributes.Temperature, tc.wantTemp)
			}
			if math.Abs(got.Attributes.Humidity-tc.wantHumidity) > 1e-9 {
				t.Errorf("humidity = %v; want %v", got.Attributes.Humidity, tc.wantHumidity)
			}
		})
	}
}

func TestFormatCommand(t *testing.T) {
	cases := []struct {
		name    string
		topic   string
		payload string
	}{
		{"rpc 指令", "v1/gateway/dev001/rpc", `{"method":"set_temp","params":{"value":30}}`},
		{"属性指令", "v1/gateway/dev001/attributes", `{"method":"set_brightness"}`},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := formatCommand(tc.topic, []byte(tc.payload))
			if !strings.Contains(got, tc.topic) {
				t.Errorf("formatCommand output %q does not contain topic %q", got, tc.topic)
			}
			if !strings.Contains(got, tc.payload) {
				t.Errorf("formatCommand output %q does not contain payload %q", got, tc.payload)
			}
		})
	}
}

func TestDeviceName_MultiDevices(t *testing.T) {
	cases := []struct {
		name    string
		base    string
		devices int
		index   int
		want    string
	}{
		{"多设备首位", "dev", 10, 0, "dev001"},
		{"多设备中位", "dev", 10, 8, "dev009"},
		{"多设备两位数", "dev", 100, 11, "dev012"},
		{"多设备三位数", "dev", 1000, 999, "dev1000"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := deviceName(tc.base, tc.devices, tc.index); got != tc.want {
				t.Errorf("deviceName(%q, %d, %d) = %q; want %q", tc.base, tc.devices, tc.index, got, tc.want)
			}
		})
	}
}

func TestSummarize_AccumulatesCounts(t *testing.T) {
	var s stats
	s.sent(0)
	s.sent(0)
	s.failed()

	got := s.snapshot(time.Now().Add(2 * time.Second))
	if got.Sent != 2 || got.Failed != 1 {
		t.Fatalf("snapshot = %+v; want Sent=2 Failed=1", got)
	}
	if got.Rate <= 0 || got.Rate > 10 {
		t.Errorf("Rate = %v; want 2 条 / 2s = 1.0 附近", got.Rate)
	}
}