package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
)

func dataTopic(mode, device string) string {
	if mode == "direct" {
		return "v1/device/" + device + "/data"
	}
	return "v1/gateway/" + device + "/data"
}

func commandTopics(mode, device string) []string {
	prefix := "v1/gateway/"
	if mode == "direct" {
		prefix = "v1/device/"
	}
	return []string{prefix + device + "/attributes", prefix + device + "/rpc"}
}

func buildReport(device string, seq int, ts int64) []byte {
	report := map[string]any{
		"device":    device,
		"seq":       seq,
		"timestamp": ts,
		"attributes": map[string]float64{
			"temperature": float64(200+seq%100) / 10.0,
			"humidity":    float64(40 + seq%50),
		},
	}
	b, _ := json.Marshal(report)
	return b
}

func formatCommand(topic string, payload []byte) string {
	return fmt.Sprintf("[device-sim] 收到指令 topic=%s payload=%s", topic, payload)
}

// deviceName 生成第 index 个设备名：多设备（devices>1）时为 base+三位零填充序号（dev001），
// 序号超出三位数按实际位数展开（dev1000）；单设备（devices<=1）返回 base 原名。
func deviceName(base string, devices, index int) string {
	if devices <= 1 {
		return base
	}
	return fmt.Sprintf("%s%03d", base, index+1)
}

// stats 汇总注入端计数：sent/failed 原子累加，snapshot 返回累计值与 sent 速率（条/秒）。
type stats struct {
	sentCount   atomic.Int64
	failedCount atomic.Int64
	start       time.Time
	once        sync.Once
}

func (s *stats) sent(cost time.Duration) {
	s.once.Do(func() { s.start = time.Now() })
	s.sentCount.Add(1)
}

func (s *stats) failed() {
	s.once.Do(func() { s.start = time.Now() })
	s.failedCount.Add(1)
}

func (s *stats) snapshot(now time.Time) struct {
	Sent   int64
	Failed int64
	Rate   float64
} {
	elapsed := now.Sub(s.start).Seconds()
	var rate float64
	if elapsed > 0 {
		rate = float64(s.sentCount.Load()) / elapsed
	}
	return struct {
		Sent   int64
		Failed int64
		Rate   float64
	}{s.sentCount.Load(), s.failedCount.Load(), rate}
}

func main() {
	broker := flag.String("broker", "127.0.0.1:1883", "MQTT broker 地址")
	device := flag.String("device", "dev001", "设备 ID 前缀（-devices>1 时作为前缀生成 dev001..devNNN，同时是首设备 MQTT clientId）")
	devices := flag.Int("devices", 1, "模拟设备数（>1 时每设备独立 MQTT 连接，命名 dev001..devNNN）")
	mode := flag.String("mode", "gateway", "设备形态：gateway|direct")
	interval := flag.Duration("interval", 5*time.Second, "数据上报间隔")
	count := flag.Int("count", 0, "每设备上报条数（0=持续上报）")
	flag.Parse()

	n := *devices
	if n < 1 {
		n = 1
	}

	var st stats
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	for i := 0; i < n; i++ {
		name := deviceName(*device, n, i)
		go runDevice(*broker, name, *mode, *interval, *count, &st, stop)
	}

	tick := time.NewTicker(5 * time.Second)
	defer tick.Stop()
	for {
		select {
		case <-stop:
			fmt.Println("[device-sim] 退出")
			return
		case t := <-tick.C:
			s := st.snapshot(t)
			fmt.Printf("[device-sim] sent=%d failed=%d rate=%.1f/s\n", s.Sent, s.Failed, s.Rate)
		}
	}
}

// runDevice 单设备循环：独立 MQTT 连接，按 interval 上报，收到 count 条后自退（0=持续）。
func runDevice(broker, device, mode string, interval time.Duration, count int, st *stats, stop <-chan os.Signal) {
	dTopic := dataTopic(mode, device)
	cTopics := commandTopics(mode, device)

	opts := mqtt.NewClientOptions()
	opts.AddBroker("tcp://" + broker)
	opts.SetClientID(device)
	opts.AutoReconnect = true
	opts.SetKeepAlive(30 * time.Second)
	opts.SetConnectTimeout(3 * time.Second)
	opts.SetOnConnectHandler(func(c mqtt.Client) {
		fmt.Printf("[device-sim] 已连接 broker=%s clientId=%s\n", broker, device)
		for _, topic := range cTopics {
			token := c.Subscribe(topic, 1, func(_ mqtt.Client, msg mqtt.Message) {
				fmt.Println(formatCommand(msg.Topic(), msg.Payload()))
			})
			token.Wait()
			if err := token.Error(); err != nil {
				fmt.Fprintf(os.Stderr, "[device-sim] 订阅失败 topic=%s: %v\n", topic, err)
				continue
			}
			fmt.Printf("[device-sim] 已订阅指令 topic=%s\n", topic)
		}
	})

	client := mqtt.NewClient(opts)
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		fmt.Fprintf(os.Stderr, "[device-sim] 连接失败 %s: %v\n", device, token.Error())
		st.failed()
		return
	}
	defer client.Disconnect(250)

	seq := 0
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			seq++
			payload := buildReport(device, seq, time.Now().UnixMilli())
			token := client.Publish(dTopic, 1, false, payload)
			token.Wait()
			if err := token.Error(); err != nil {
				fmt.Fprintf(os.Stderr, "[device-sim] 上报失败 %s seq=%d: %v\n", device, seq, err)
				st.failed()
				continue
			}
			st.sent(0)
			if seq%50 == 0 {
				fmt.Printf("[device-sim] %s 已上报 seq=%d\n", device, seq)
			}
			if count > 0 && seq >= count {
				return
			}
		}
	}
}
