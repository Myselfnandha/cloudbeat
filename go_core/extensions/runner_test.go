package extensions

import (
	"testing"
)

func TestExtensionRunner_LoadAndExecute(t *testing.T) {
	manifestJSON := `{
		"name": "mock-provider",
		"displayName": "Mock Provider",
		"version": "1.0.0",
		"type": ["metadata_provider"],
		"minAppVersion": "1.0.0"
	}`

	jsSource := `
		var currentSettings = {};
		function initialize(settings) {
			currentSettings = settings || {};
			return true;
		}
		function getSetting(key) {
			return currentSettings[key];
		}
		function calculateMultiplier(a, b) {
			return a * b;
		}
		function cleanup() {
			currentSettings = {};
		}
	`

	runner, err := LoadFromSource(manifestJSON, jsSource)
	if err != nil {
		t.Fatalf("failed to load runner: %v", err)
	}

	if runner.Manifest.Name != "mock-provider" {
		t.Errorf("expected manifest name 'mock-provider', got '%s'", runner.Manifest.Name)
	}

	ok, err := runner.Initialize(map[string]interface{}{
		"apiBaseUrl": "https://custom.api.com",
	})
	if err != nil || !ok {
		t.Fatalf("initialize failed: %v", err)
	}

	val, err := runner.CallFunction("getSetting", "apiBaseUrl")
	if err != nil {
		t.Fatalf("call getSetting failed: %v", err)
	}
	if val.String() != "https://custom.api.com" {
		t.Errorf("expected 'https://custom.api.com', got '%s'", val.String())
	}

	multVal, err := runner.CallFunction("calculateMultiplier", 6, 7)
	if err != nil {
		t.Fatalf("call calculateMultiplier failed: %v", err)
	}
	if multVal.ToInteger() != 42 {
		t.Errorf("expected 42, got %d", multVal.ToInteger())
	}

	runner.Cleanup()
}
