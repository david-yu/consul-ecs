package config

import (
	"io/ioutil"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

var config = &Config{
	Secret: AclTokenSecret{
		Provider: "secret-manager",
		Configuration: SecretConfiguration{
			Prefix:                     "asdf",
			ConsulClientTokenSecretARN: "ARN",
		},
	},
	Mesh: Mesh{
		Service: ServiceRegistration{
			Name: "blah",
			Port: 1234,
			Tags: []string{"tag1"},
			Meta: map[string]string{"a": "1"},
		},
		Sidecar: SidecarProxyRegistration{
			Proxy: &AgentServiceConnectProxyConfig{
				Upstreams: []Upstream{
					{
						DestinationName: "asdf",
						LocalBindPort:   543,
					},
				},
			},
		},
		HealthSyncContainers: []string{"container1"},
		BootstrapDir:         "/consul/",
	},
}

func TestParse(t *testing.T) {
	rawConfig := OpenFile(t, "resources/test_config.json")
	parsedConfig, err := Parse(rawConfig)
	require.NoError(t, err)
	require.Equal(t, config, parsedConfig)
}

func TestParseErrors(t *testing.T) {
	rawConfig := OpenFile(t, "resources/test_config_missing_fields.json")
	// TODO test multiple errors
	_, err := Parse(rawConfig)
	require.Error(t, err)
	require.Contains(t, err.Error(), "aclTokenSecret: provider is required")
}

func TestFromEnv(t *testing.T) {
	rawConfig := OpenFile(t, "resources/test_config.json")
	err := os.Setenv(ConfigEnvironmentVariable, rawConfig)
	require.NoError(t, err)
	t.Cleanup(func() {
		err := os.Unsetenv(ConfigEnvironmentVariable)
		require.NoError(t, err)
	})

	parsedConfig, err := FromEnv()
	require.NoError(t, err)
	require.Equal(t, config, parsedConfig)
}

func OpenFile(t *testing.T, path string) string {
	byteFile, err := ioutil.ReadFile(path)
	require.NoError(t, err)
	return string(byteFile)
}
