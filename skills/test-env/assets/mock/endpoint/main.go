package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net"
	"os"

	pb "rbedge-mock-endpoint/pb"

	"google.golang.org/grpc"
)

var forwardTypeNames = map[uint32]string{
	1: "FORWARD_DATA",
	2: "FORWARD_RESPONSE",
	3: "FORWARD_EVENT",
	4: "FORWARD_ONLINE",
	5: "FORWARD_OFFLINE",
}

type endPointServer struct {
	pb.UnimplementedEndPointProviderServer
	out io.Writer
}

func (s *endPointServer) RbIotMessage(_ context.Context, req *pb.RequestData) (*pb.ResponseData, error) {
	name, ok := forwardTypeNames[req.GetType()]
	if !ok {
		name = fmt.Sprintf("UNKNOWN(%d)", req.GetType())
	}
	fmt.Fprintf(s.out, "[mock-endpoint] type=%s topic=%s payload_bytes=%d\n",
		name, req.GetMessage().GetTopic(), len(req.GetMessage().GetPayload()))
	return &pb.ResponseData{Code: 200, Data: "mock-ok"}, nil
}

func newGRPCServer(out io.Writer) *grpc.Server {
	srv := grpc.NewServer(grpc.MaxRecvMsgSize(256 * 1024 * 1024))
	pb.RegisterEndPointProviderServer(srv, &endPointServer{out: out})
	return srv
}

func main() {
	addr := flag.String("addr", ":9096", "gRPC listen address")
	flag.Parse()

	lis, err := net.Listen("tcp", *addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "listen %s: %v\n", *addr, err)
		os.Exit(1)
	}
	fmt.Printf("[mock-endpoint] listening on %s (gRPC)\n", *addr)
	if err := newGRPCServer(os.Stdout).Serve(lis); err != nil {
		fmt.Fprintf(os.Stderr, "serve: %v\n", err)
		os.Exit(1)
	}
}
