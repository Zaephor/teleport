// Copyright 2023 Gravitational, Inc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Code generated by protoc-gen-go-grpc. DO NOT EDIT.
// versions:
// - protoc-gen-go-grpc v1.3.0
// - protoc             (unknown)
// source: teleport/dbobjectimportrule/v1/dbobjectimportrule_service.proto

package dbobjectimportrulev1

import (
	context "context"
	grpc "google.golang.org/grpc"
	codes "google.golang.org/grpc/codes"
	status "google.golang.org/grpc/status"
	emptypb "google.golang.org/protobuf/types/known/emptypb"
)

// This is a compile-time assertion to ensure that this generated file
// is compatible with the grpc package it is being compiled against.
// Requires gRPC-Go v1.32.0 or later.
const _ = grpc.SupportPackageIsVersion7

const (
	DatabaseObjectImportRuleService_GetDatabaseObjectImportRule_FullMethodName    = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/GetDatabaseObjectImportRule"
	DatabaseObjectImportRuleService_ListDatabaseObjectImportRules_FullMethodName  = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/ListDatabaseObjectImportRules"
	DatabaseObjectImportRuleService_CreateDatabaseObjectImportRule_FullMethodName = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/CreateDatabaseObjectImportRule"
	DatabaseObjectImportRuleService_UpdateDatabaseObjectImportRule_FullMethodName = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/UpdateDatabaseObjectImportRule"
	DatabaseObjectImportRuleService_UpsertDatabaseObjectImportRule_FullMethodName = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/UpsertDatabaseObjectImportRule"
	DatabaseObjectImportRuleService_DeleteDatabaseObjectImportRule_FullMethodName = "/teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService/DeleteDatabaseObjectImportRule"
)

// DatabaseObjectImportRuleServiceClient is the client API for DatabaseObjectImportRuleService service.
//
// For semantics around ctx use and closing/ending streaming RPCs, please refer to https://pkg.go.dev/google.golang.org/grpc/?tab=doc#ClientConn.NewStream.
type DatabaseObjectImportRuleServiceClient interface {
	// GetDatabaseObjectImportRule is used to query a DatabaseObjectImportRule resource by its name.
	//
	// This will return a NotFound error if the specified DatabaseObjectImportRule does not exist.
	GetDatabaseObjectImportRule(ctx context.Context, in *GetDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error)
	// ListDatabaseObjectImportRules is used to query DatabaseObjectImportRules.
	//
	// Follows the pagination semantics of
	// https://cloud.google.com/apis/design/standard_methods#list.
	ListDatabaseObjectImportRules(ctx context.Context, in *ListDatabaseObjectImportRulesRequest, opts ...grpc.CallOption) (*ListDatabaseObjectImportRulesResponse, error)
	// CreateDatabaseObjectImportRule is used to create a DatabaseObjectImportRule.
	//
	// This will return an error if a DatabaseObjectImportRule by that name already exists.
	CreateDatabaseObjectImportRule(ctx context.Context, in *CreateDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error)
	// UpdateDatabaseObjectImportRule is used to modify an existing DatabaseObjectImportRule.
	UpdateDatabaseObjectImportRule(ctx context.Context, in *UpdateDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error)
	// UpsertDatabaseObjectImportRule is used to create or replace an existing DatabaseObjectImportRule.
	//
	// Prefer using CreateDatabaseObjectImportRule and UpdateDatabaseObjectImportRule.
	UpsertDatabaseObjectImportRule(ctx context.Context, in *UpsertDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error)
	// DeleteDatabaseObjectImportRule is used to delete a specific DatabaseObjectImportRule.
	//
	// This will return a NotFound error if the specified DatabaseObjectImportRule does not exist.
	DeleteDatabaseObjectImportRule(ctx context.Context, in *DeleteDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*emptypb.Empty, error)
}

type databaseObjectImportRuleServiceClient struct {
	cc grpc.ClientConnInterface
}

func NewDatabaseObjectImportRuleServiceClient(cc grpc.ClientConnInterface) DatabaseObjectImportRuleServiceClient {
	return &databaseObjectImportRuleServiceClient{cc}
}

func (c *databaseObjectImportRuleServiceClient) GetDatabaseObjectImportRule(ctx context.Context, in *GetDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error) {
	out := new(DatabaseObjectImportRule)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_GetDatabaseObjectImportRule_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *databaseObjectImportRuleServiceClient) ListDatabaseObjectImportRules(ctx context.Context, in *ListDatabaseObjectImportRulesRequest, opts ...grpc.CallOption) (*ListDatabaseObjectImportRulesResponse, error) {
	out := new(ListDatabaseObjectImportRulesResponse)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_ListDatabaseObjectImportRules_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *databaseObjectImportRuleServiceClient) CreateDatabaseObjectImportRule(ctx context.Context, in *CreateDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error) {
	out := new(DatabaseObjectImportRule)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_CreateDatabaseObjectImportRule_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *databaseObjectImportRuleServiceClient) UpdateDatabaseObjectImportRule(ctx context.Context, in *UpdateDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error) {
	out := new(DatabaseObjectImportRule)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_UpdateDatabaseObjectImportRule_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *databaseObjectImportRuleServiceClient) UpsertDatabaseObjectImportRule(ctx context.Context, in *UpsertDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*DatabaseObjectImportRule, error) {
	out := new(DatabaseObjectImportRule)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_UpsertDatabaseObjectImportRule_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *databaseObjectImportRuleServiceClient) DeleteDatabaseObjectImportRule(ctx context.Context, in *DeleteDatabaseObjectImportRuleRequest, opts ...grpc.CallOption) (*emptypb.Empty, error) {
	out := new(emptypb.Empty)
	err := c.cc.Invoke(ctx, DatabaseObjectImportRuleService_DeleteDatabaseObjectImportRule_FullMethodName, in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

// DatabaseObjectImportRuleServiceServer is the server API for DatabaseObjectImportRuleService service.
// All implementations must embed UnimplementedDatabaseObjectImportRuleServiceServer
// for forward compatibility
type DatabaseObjectImportRuleServiceServer interface {
	// GetDatabaseObjectImportRule is used to query a DatabaseObjectImportRule resource by its name.
	//
	// This will return a NotFound error if the specified DatabaseObjectImportRule does not exist.
	GetDatabaseObjectImportRule(context.Context, *GetDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error)
	// ListDatabaseObjectImportRules is used to query DatabaseObjectImportRules.
	//
	// Follows the pagination semantics of
	// https://cloud.google.com/apis/design/standard_methods#list.
	ListDatabaseObjectImportRules(context.Context, *ListDatabaseObjectImportRulesRequest) (*ListDatabaseObjectImportRulesResponse, error)
	// CreateDatabaseObjectImportRule is used to create a DatabaseObjectImportRule.
	//
	// This will return an error if a DatabaseObjectImportRule by that name already exists.
	CreateDatabaseObjectImportRule(context.Context, *CreateDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error)
	// UpdateDatabaseObjectImportRule is used to modify an existing DatabaseObjectImportRule.
	UpdateDatabaseObjectImportRule(context.Context, *UpdateDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error)
	// UpsertDatabaseObjectImportRule is used to create or replace an existing DatabaseObjectImportRule.
	//
	// Prefer using CreateDatabaseObjectImportRule and UpdateDatabaseObjectImportRule.
	UpsertDatabaseObjectImportRule(context.Context, *UpsertDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error)
	// DeleteDatabaseObjectImportRule is used to delete a specific DatabaseObjectImportRule.
	//
	// This will return a NotFound error if the specified DatabaseObjectImportRule does not exist.
	DeleteDatabaseObjectImportRule(context.Context, *DeleteDatabaseObjectImportRuleRequest) (*emptypb.Empty, error)
	mustEmbedUnimplementedDatabaseObjectImportRuleServiceServer()
}

// UnimplementedDatabaseObjectImportRuleServiceServer must be embedded to have forward compatible implementations.
type UnimplementedDatabaseObjectImportRuleServiceServer struct {
}

func (UnimplementedDatabaseObjectImportRuleServiceServer) GetDatabaseObjectImportRule(context.Context, *GetDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error) {
	return nil, status.Errorf(codes.Unimplemented, "method GetDatabaseObjectImportRule not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) ListDatabaseObjectImportRules(context.Context, *ListDatabaseObjectImportRulesRequest) (*ListDatabaseObjectImportRulesResponse, error) {
	return nil, status.Errorf(codes.Unimplemented, "method ListDatabaseObjectImportRules not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) CreateDatabaseObjectImportRule(context.Context, *CreateDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error) {
	return nil, status.Errorf(codes.Unimplemented, "method CreateDatabaseObjectImportRule not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) UpdateDatabaseObjectImportRule(context.Context, *UpdateDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error) {
	return nil, status.Errorf(codes.Unimplemented, "method UpdateDatabaseObjectImportRule not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) UpsertDatabaseObjectImportRule(context.Context, *UpsertDatabaseObjectImportRuleRequest) (*DatabaseObjectImportRule, error) {
	return nil, status.Errorf(codes.Unimplemented, "method UpsertDatabaseObjectImportRule not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) DeleteDatabaseObjectImportRule(context.Context, *DeleteDatabaseObjectImportRuleRequest) (*emptypb.Empty, error) {
	return nil, status.Errorf(codes.Unimplemented, "method DeleteDatabaseObjectImportRule not implemented")
}
func (UnimplementedDatabaseObjectImportRuleServiceServer) mustEmbedUnimplementedDatabaseObjectImportRuleServiceServer() {
}

// UnsafeDatabaseObjectImportRuleServiceServer may be embedded to opt out of forward compatibility for this service.
// Use of this interface is not recommended, as added methods to DatabaseObjectImportRuleServiceServer will
// result in compilation errors.
type UnsafeDatabaseObjectImportRuleServiceServer interface {
	mustEmbedUnimplementedDatabaseObjectImportRuleServiceServer()
}

func RegisterDatabaseObjectImportRuleServiceServer(s grpc.ServiceRegistrar, srv DatabaseObjectImportRuleServiceServer) {
	s.RegisterService(&DatabaseObjectImportRuleService_ServiceDesc, srv)
}

func _DatabaseObjectImportRuleService_GetDatabaseObjectImportRule_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(GetDatabaseObjectImportRuleRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).GetDatabaseObjectImportRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_GetDatabaseObjectImportRule_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).GetDatabaseObjectImportRule(ctx, req.(*GetDatabaseObjectImportRuleRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _DatabaseObjectImportRuleService_ListDatabaseObjectImportRules_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(ListDatabaseObjectImportRulesRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).ListDatabaseObjectImportRules(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_ListDatabaseObjectImportRules_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).ListDatabaseObjectImportRules(ctx, req.(*ListDatabaseObjectImportRulesRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _DatabaseObjectImportRuleService_CreateDatabaseObjectImportRule_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(CreateDatabaseObjectImportRuleRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).CreateDatabaseObjectImportRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_CreateDatabaseObjectImportRule_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).CreateDatabaseObjectImportRule(ctx, req.(*CreateDatabaseObjectImportRuleRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _DatabaseObjectImportRuleService_UpdateDatabaseObjectImportRule_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(UpdateDatabaseObjectImportRuleRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).UpdateDatabaseObjectImportRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_UpdateDatabaseObjectImportRule_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).UpdateDatabaseObjectImportRule(ctx, req.(*UpdateDatabaseObjectImportRuleRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _DatabaseObjectImportRuleService_UpsertDatabaseObjectImportRule_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(UpsertDatabaseObjectImportRuleRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).UpsertDatabaseObjectImportRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_UpsertDatabaseObjectImportRule_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).UpsertDatabaseObjectImportRule(ctx, req.(*UpsertDatabaseObjectImportRuleRequest))
	}
	return interceptor(ctx, in, info, handler)
}

func _DatabaseObjectImportRuleService_DeleteDatabaseObjectImportRule_Handler(srv interface{}, ctx context.Context, dec func(interface{}) error, interceptor grpc.UnaryServerInterceptor) (interface{}, error) {
	in := new(DeleteDatabaseObjectImportRuleRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if interceptor == nil {
		return srv.(DatabaseObjectImportRuleServiceServer).DeleteDatabaseObjectImportRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{
		Server:     srv,
		FullMethod: DatabaseObjectImportRuleService_DeleteDatabaseObjectImportRule_FullMethodName,
	}
	handler := func(ctx context.Context, req interface{}) (interface{}, error) {
		return srv.(DatabaseObjectImportRuleServiceServer).DeleteDatabaseObjectImportRule(ctx, req.(*DeleteDatabaseObjectImportRuleRequest))
	}
	return interceptor(ctx, in, info, handler)
}

// DatabaseObjectImportRuleService_ServiceDesc is the grpc.ServiceDesc for DatabaseObjectImportRuleService service.
// It's only intended for direct use with grpc.RegisterService,
// and not to be introspected or modified (even as a copy)
var DatabaseObjectImportRuleService_ServiceDesc = grpc.ServiceDesc{
	ServiceName: "teleport.dbobjectimportrule.v1.DatabaseObjectImportRuleService",
	HandlerType: (*DatabaseObjectImportRuleServiceServer)(nil),
	Methods: []grpc.MethodDesc{
		{
			MethodName: "GetDatabaseObjectImportRule",
			Handler:    _DatabaseObjectImportRuleService_GetDatabaseObjectImportRule_Handler,
		},
		{
			MethodName: "ListDatabaseObjectImportRules",
			Handler:    _DatabaseObjectImportRuleService_ListDatabaseObjectImportRules_Handler,
		},
		{
			MethodName: "CreateDatabaseObjectImportRule",
			Handler:    _DatabaseObjectImportRuleService_CreateDatabaseObjectImportRule_Handler,
		},
		{
			MethodName: "UpdateDatabaseObjectImportRule",
			Handler:    _DatabaseObjectImportRuleService_UpdateDatabaseObjectImportRule_Handler,
		},
		{
			MethodName: "UpsertDatabaseObjectImportRule",
			Handler:    _DatabaseObjectImportRuleService_UpsertDatabaseObjectImportRule_Handler,
		},
		{
			MethodName: "DeleteDatabaseObjectImportRule",
			Handler:    _DatabaseObjectImportRuleService_DeleteDatabaseObjectImportRule_Handler,
		},
	},
	Streams:  []grpc.StreamDesc{},
	Metadata: "teleport/dbobjectimportrule/v1/dbobjectimportrule_service.proto",
}
