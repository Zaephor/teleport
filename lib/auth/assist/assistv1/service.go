/*
 *
 * Copyright 2023 Gravitational, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

package assistv1

import (
	"context"

	"github.com/gravitational/trace"
	"github.com/sirupsen/logrus"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/gravitational/teleport/api/defaults"
	"github.com/gravitational/teleport/api/gen/proto/go/assist/v1"
	"github.com/gravitational/teleport/api/types"
	"github.com/gravitational/teleport/lib/ai"
	embeddinglib "github.com/gravitational/teleport/lib/ai/embedding"
	"github.com/gravitational/teleport/lib/authz"
	"github.com/gravitational/teleport/lib/services"
)

// ServiceConfig holds configuration options for
// the assist gRPC service.
type ServiceConfig struct {
	Backend        services.Assistant
	Embeddings     *ai.SimpleRetriever
	Embedder       embeddinglib.Embedder
	Authorizer     authz.Authorizer
	Logger         *logrus.Entry
	ResourceGetter ResourceGetter
}

// ResourceGetter represents a subset of the auth.Cache interface.
// Created to avoid circular dependencies.
type ResourceGetter interface {
	GetNode(ctx context.Context, namespace, name string) (types.Server, error)
}

// Service implements the teleport.assist.v1.AssistService RPC service.
type Service struct {
	assist.UnimplementedAssistServiceServer
	assist.UnimplementedAssistEmbeddingServiceServer

	backend    services.Assistant
	embeddings *ai.SimpleRetriever
	// embedder is used to embed text into a vector.
	// It can be nil if the OpenAI API key is not set.
	embedder       embeddinglib.Embedder
	authorizer     authz.Authorizer
	log            *logrus.Entry
	resourceGetter ResourceGetter
}

// NewService returns a new assist gRPC service.
func NewService(cfg *ServiceConfig) (*Service, error) {
	switch {
	case cfg.Backend == nil:
		return nil, trace.BadParameter("backend is required")
	case cfg.Embeddings == nil:
		return nil, trace.BadParameter("embeddings is required")
	case cfg.Authorizer == nil:
		return nil, trace.BadParameter("authorizer is required")
	case cfg.ResourceGetter == nil:
		return nil, trace.BadParameter("resource getter is required")
	case cfg.Logger == nil:
		cfg.Logger = logrus.WithField(trace.Component, "assist.service")
	}
	// Embedder can be nil is the OpenAI API key is not set.

	return &Service{
		backend:        cfg.Backend,
		embeddings:     cfg.Embeddings,
		embedder:       cfg.Embedder,
		authorizer:     cfg.Authorizer,
		resourceGetter: cfg.ResourceGetter,
		log:            cfg.Logger,
	}, nil
}

// CreateAssistantConversation creates a new conversation entry in the backend.
func (a *Service) CreateAssistantConversation(ctx context.Context, req *assist.CreateAssistantConversationRequest) (*assist.CreateAssistantConversationResponse, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbCreate)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to create conversation for user %q", authCtx.User.GetName(), req.Username)
	}

	resp, err := a.backend.CreateAssistantConversation(ctx, req)
	return resp, trace.Wrap(err)
}

// UpdateAssistantConversationInfo updates the conversation info for a conversation.
func (a *Service) UpdateAssistantConversationInfo(ctx context.Context, req *assist.UpdateAssistantConversationInfoRequest) (*emptypb.Empty, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbUpdate)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to update conversation for user %q", authCtx.User.GetName(), req.Username)
	}

	err = a.backend.UpdateAssistantConversationInfo(ctx, req)
	if err != nil {
		return &emptypb.Empty{}, trace.Wrap(err)
	}

	return &emptypb.Empty{}, nil
}

// GetAssistantConversations returns all conversations started by a user.
func (a *Service) GetAssistantConversations(ctx context.Context, req *assist.GetAssistantConversationsRequest) (*assist.GetAssistantConversationsResponse, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbList)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to list conversations for user %q", authCtx.User.GetName(), req.GetUsername())
	}

	resp, err := a.backend.GetAssistantConversations(ctx, req)
	return resp, trace.Wrap(err)
}

// DeleteAssistantConversation deletes a conversation entry and associated messages from the backend.
func (a *Service) DeleteAssistantConversation(ctx context.Context, req *assist.DeleteAssistantConversationRequest) (*emptypb.Empty, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbDelete)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to delete conversation for user %q", authCtx.User.GetName(), req.GetUsername())
	}

	return &emptypb.Empty{}, trace.Wrap(a.backend.DeleteAssistantConversation(ctx, req))
}

// GetAssistantMessages returns all messages with given conversation ID.
func (a *Service) GetAssistantMessages(ctx context.Context, req *assist.GetAssistantMessagesRequest) (*assist.GetAssistantMessagesResponse, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbRead)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to get messages for user %q", authCtx.User.GetName(), req.GetUsername())
	}

	resp, err := a.backend.GetAssistantMessages(ctx, req)
	return resp, trace.Wrap(err)
}

// CreateAssistantMessage adds the message to the backend.
func (a *Service) CreateAssistantMessage(ctx context.Context, req *assist.CreateAssistantMessageRequest) (*emptypb.Empty, error) {
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindAssistant, types.VerbCreate)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if userHasAccess(authCtx, req) {
		return nil, trace.AccessDenied("user %q is not allowed to create message for user %q", authCtx.User.GetName(), req.GetUsername())
	}

	return &emptypb.Empty{}, trace.Wrap(a.backend.CreateAssistantMessage(ctx, req))
}

// IsAssistEnabled returns true if the assist is enabled or not on the auth level.
func (a *Service) IsAssistEnabled(ctx context.Context, _ *assist.IsAssistEnabledRequest) (*assist.IsAssistEnabledResponse, error) {
	// If the embedder is not configured, the assist is not enabled as we cannot compute embeddings.
	if a.embedder == nil {
		return &assist.IsAssistEnabledResponse{Enabled: false}, nil
	}

	authCtx, err := a.authorizer.Authorize(ctx)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	// Check if this endpoint is called by a user or Proxy.
	if authz.IsLocalUser(*authCtx) {
		checkErr := authCtx.Checker.CheckAccessToRule(
			&services.Context{User: authCtx.User},
			defaults.Namespace, types.KindAssistant, types.VerbRead,
			false, /* silent */
		)
		if checkErr != nil {
			return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
		}
	} else {
		// This endpoint is called from Proxy to check if the assist is enabled.
		// Proxy credentials are used instead of the user credentials.
		requestedByProxy := authz.HasBuiltinRole(*authCtx, string(types.RoleProxy))
		if !requestedByProxy {
			return nil, trace.AccessDenied("only proxy is allowed to call IsAssistEnabled endpoint")
		}
	}

	// Check if assist can use the backend.
	return a.backend.IsAssistEnabled(ctx)
}

func (a *Service) GetAssistantEmbeddings(ctx context.Context, msg *assist.GetAssistantEmbeddingsRequest) (*assist.GetAssistantEmbeddingsResponse, error) {
	// TODO(jakule): The kind needs to be updated when we add more resources.
	authCtx, err := authz.AuthorizeWithVerbs(ctx, a.log, a.authorizer, true, types.KindNode, types.VerbRead, types.VerbList)
	if err != nil {
		return nil, authz.ConvertAuthorizerError(ctx, a.log, err)
	}

	if a.embedder == nil {
		return nil, trace.BadParameter("assist is not configured in auth server")
	}

	// Call the openAI API to get the embeddings for the query.
	embeddings, err := a.embedder.ComputeEmbeddings(ctx, []string{msg.Query})
	if err != nil {
		return nil, trace.Wrap(err)
	}
	if len(embeddings) == 0 {
		return nil, trace.NotFound("OpenAI embeddings returned no results")
	}

	// Use default values for the id and content, as we only care about the embeddings.
	queryEmbeddings := embeddinglib.NewEmbedding(msg.Kind, "", embeddings[0], [32]byte{})
	documents := a.embeddings.GetRelevant(queryEmbeddings, int(msg.Limit), func(id string, embedding *embeddinglib.Embedding) bool {
		// Run RBAC check on the embedded resource.
		node, err := a.resourceGetter.GetNode(ctx, defaults.Namespace, embedding.GetEmbeddedID())
		if err != nil {
			a.log.Tracef("failed to get node %q: %v", embedding.GetName(), err)
			return false
		}
		return authCtx.Checker.CheckAccess(node, services.AccessState{MFAVerified: true}) == nil
	})

	protoDocs := make([]*assist.EmbeddedDocument, 0, len(documents))
	for _, doc := range documents {
		node, err := a.resourceGetter.GetNode(ctx, defaults.Namespace, doc.GetEmbeddedID())
		if err != nil {
			return nil, trace.Wrap(err)
		}

		content, err := embeddinglib.SerializeNode(node)
		if err != nil {
			return nil, trace.Wrap(err)
		}
		protoDocs = append(protoDocs, &assist.EmbeddedDocument{
			Id:              doc.GetEmbeddedID(),
			Content:         string(content),
			SimilarityScore: float32(doc.SimilarityScore),
		})
	}

	return &assist.GetAssistantEmbeddingsResponse{
		Embeddings: protoDocs,
	}, nil
}

// userHasAccess returns true if the user should have access to the resource.
func userHasAccess(authCtx *authz.Context, req interface{ GetUsername() string }) bool {
	return !authz.IsCurrentUser(*authCtx, req.GetUsername()) && !authz.HasBuiltinRole(*authCtx, string(types.RoleAdmin))
}