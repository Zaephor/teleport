/*
Copyright 2023 Gravitational, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package types

import (
	"encoding/json"
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v2"

	"github.com/gravitational/teleport/api/types/wrappers"
)

func TestAccessRequestConditionsIsEmpty(t *testing.T) {
	tests := []struct {
		name     string
		arc      AccessRequestConditions
		expected bool
	}{
		{
			name:     "empty",
			arc:      AccessRequestConditions{},
			expected: true,
		},
		{
			name: "annotations",
			arc: AccessRequestConditions{
				Annotations: wrappers.Traits{
					"test": []string{"test"},
				},
			},
			expected: false,
		},
		{
			name: "claims to roles",
			arc: AccessRequestConditions{
				ClaimsToRoles: []ClaimMapping{
					{},
				},
			},
			expected: false,
		},
		{
			name: "roles",
			arc: AccessRequestConditions{
				Roles: []string{"test"},
			},
			expected: false,
		},
		{
			name: "search as roles",
			arc: AccessRequestConditions{
				SearchAsRoles: []string{"test"},
			},
			expected: false,
		},
		{
			name: "suggested reviewers",
			arc: AccessRequestConditions{
				SuggestedReviewers: []string{"test"},
			},
			expected: false,
		},
		{
			name: "thresholds",
			arc: AccessRequestConditions{
				Thresholds: []AccessReviewThreshold{
					{
						Name: "test",
					},
				},
			},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			require.Equal(t, test.expected, test.arc.IsEmpty())
		})
	}
}

func TestAccessReviewConditionsIsEmpty(t *testing.T) {
	tests := []struct {
		name     string
		arc      AccessReviewConditions
		expected bool
	}{
		{
			name:     "empty",
			arc:      AccessReviewConditions{},
			expected: true,
		},
		{
			name: "claims to roles",
			arc: AccessReviewConditions{
				ClaimsToRoles: []ClaimMapping{
					{},
				},
			},
			expected: false,
		},
		{
			name: "preview as roles",
			arc: AccessReviewConditions{
				PreviewAsRoles: []string{"test"},
			},
			expected: false,
		},
		{
			name: "roles",
			arc: AccessReviewConditions{
				Roles: []string{"test"},
			},
			expected: false,
		},
		{
			name: "where",
			arc: AccessReviewConditions{
				Where: "test",
			},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			require.Equal(t, test.expected, test.arc.IsEmpty())
		})
	}
}

func TestMarshallCreateHostUserModeJSON(t *testing.T) {
	for _, tc := range []struct {
		input    CreateHostUserMode
		expected string
	}{
		{input: CreateHostUserMode_HOST_USER_MODE_OFF, expected: "off"},
		{input: CreateHostUserMode_HOST_USER_MODE_UNSPECIFIED, expected: ""},
		{input: CreateHostUserMode_HOST_USER_MODE_DROP, expected: "drop"},
		{input: CreateHostUserMode_HOST_USER_MODE_KEEP, expected: "keep"},
	} {
		got, err := json.Marshal(&tc.input)
		require.NoError(t, err)
		require.Equal(t, fmt.Sprintf("%q", tc.expected), string(got))
	}

}

func TestMarshallCreateHostUserModeYAML(t *testing.T) {
	for _, tc := range []struct {
		input    CreateHostUserMode
		expected string
	}{
		{input: CreateHostUserMode_HOST_USER_MODE_OFF, expected: "\"off\""},
		{input: CreateHostUserMode_HOST_USER_MODE_UNSPECIFIED, expected: "\"\""},
		{input: CreateHostUserMode_HOST_USER_MODE_DROP, expected: "drop"},
		{input: CreateHostUserMode_HOST_USER_MODE_KEEP, expected: "keep"},
	} {
		got, err := yaml.Marshal(&tc.input)
		require.NoError(t, err)
		require.Equal(t, fmt.Sprintf("%s\n", tc.expected), string(got))
	}

}

func TestUnmarshallCreateHostUserModeJSON(t *testing.T) {
	for _, tc := range []struct {
		expected CreateHostUserMode
		input    string
	}{
		{expected: CreateHostUserMode_HOST_USER_MODE_OFF, input: "off"},
		{expected: CreateHostUserMode_HOST_USER_MODE_UNSPECIFIED, input: ""},
		{expected: CreateHostUserMode_HOST_USER_MODE_DROP, input: "drop"},
		{expected: CreateHostUserMode_HOST_USER_MODE_KEEP, input: "keep"},
	} {
		var got CreateHostUserMode
		err := json.Unmarshal([]byte(fmt.Sprintf("%q", tc.input)), &got)
		require.NoError(t, err)
		require.Equal(t, tc.expected, got)
	}
}

func TestUnmarshallCreateHostUserModeYAML(t *testing.T) {
	for _, tc := range []struct {
		expected CreateHostUserMode
		input    string
	}{
		{expected: CreateHostUserMode_HOST_USER_MODE_OFF, input: "\"off\""},
		{expected: CreateHostUserMode_HOST_USER_MODE_OFF, input: "off"},
		{expected: CreateHostUserMode_HOST_USER_MODE_UNSPECIFIED, input: "\"\""},
		{expected: CreateHostUserMode_HOST_USER_MODE_DROP, input: "drop"},
		{expected: CreateHostUserMode_HOST_USER_MODE_KEEP, input: "keep"},
	} {
		var got CreateHostUserMode
		err := yaml.Unmarshal([]byte(tc.input), &got)
		require.NoError(t, err)
		require.Equal(t, tc.expected, got)
	}
}