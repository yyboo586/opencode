package main

import (
	"bytes"
	"context"
	"net"
	"strings"
	"testing"

	pb "rbedge-mock-endpoint/pb"

	"google.golang.org/grpc"
	"google.golang.org/grpc/test/bufconn"
)

func callRbIotMessage(t *testing.T, out *bytes.Buffer, req *pb.RequestData) *pb.ResponseData {
	t.Helper()

	srv := newGRPCServer(out)
	lis := bufconn.Listen(1024 * 1024)
	go func() {
		_ = srv.Serve(lis)
	}()
	t.Cleanup(srv.Stop)

	conn, err := grpc.DialContext(context.Background(), "bufnet",
		grpc.WithInsecure(),
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) {
			return lis.Dial()
		}),
	)
	if err != nil {
		t.Fatalf("dial mock endpoint: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })

	resp, err := pb.NewEndPointProviderClient(conn).RbIotMessage(context.Background(), req)
	if err != nil {
		t.Fatalf("RbIotMessage: %v", err)
	}
	return resp
}

func TestRbIotMessage_AckAllForwardTypes(t *testing.T) {
	cases := []struct {
		name    string
		typ     uint32
		wantLog string
	}{
		{"FORWARD_DATA", 1, "FORWARD_DATA"},
		{"FORWARD_RESPONSE", 2, "FORWARD_RESPONSE"},
		{"FORWARD_EVENT", 3, "FORWARD_EVENT"},
		{"FORWARD_ONLINE", 4, "FORWARD_ONLINE"},
		{"FORWARD_OFFLINE", 5, "FORWARD_OFFLINE"},
		{"UNKNOWN", 99, "UNKNOWN(99)"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			resp := callRbIotMessage(t, &out, &pb.RequestData{
				Type: tc.typ,
				Message: &pb.Message{
					Topic:   "v1/gateway/dev001/data",
					Payload: []byte("hello"),
				},
			})

			if resp.GetCode() != 200 {
				t.Errorf("resp.Code = %d; want 200", resp.GetCode())
			}
			if resp.GetData() != "mock-ok" {
				t.Errorf("resp.Data = %q; want %q", resp.GetData(), "mock-ok")
			}
			if !strings.Contains(out.String(), tc.wantLog) {
				t.Errorf("log output %q does not contain %q", out.String(), tc.wantLog)
			}
			if !strings.Contains(out.String(), "v1/gateway/dev001/data") {
				t.Errorf("log output %q does not contain topic", out.String())
			}
		})
	}
}

func TestRbIotMessage_NilMessage(t *testing.T) {
	var out bytes.Buffer
	resp := callRbIotMessage(t, &out, &pb.RequestData{Type: 4})

	if resp.GetCode() != 200 {
		t.Errorf("resp.Code = %d; want 200", resp.GetCode())
	}
	if !strings.Contains(out.String(), "FORWARD_ONLINE") {
		t.Errorf("log output %q does not contain FORWARD_ONLINE", out.String())
	}
	if !strings.Contains(out.String(), "payload_bytes=0") {
		t.Errorf("log output %q does not report payload_bytes=0", out.String())
	}
}
