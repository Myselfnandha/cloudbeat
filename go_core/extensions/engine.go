package extensions

import (
	"fmt"
	"sync"
)

var (
	runnersMu sync.RWMutex
	runners   = make(map[string]*Runner)
)

// LoadExtension loads an extension and stores it in the global registry
func LoadExtension(name, manifestJSON, jsSource string) error {
	runner, err := LoadFromSource(manifestJSON, jsSource)
	if err != nil {
		return err
	}

	runnersMu.Lock()
	runners[name] = runner
	runnersMu.Unlock()
	return nil
}

// ExecuteCommand runs a method on a loaded extension
func ExecuteCommand(extension, method string, args []interface{}) (interface{}, error) {
	runnersMu.RLock()
	runner, ok := runners[extension]
	runnersMu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("extension %s not loaded", extension)
	}

	val, err := runner.CallFunction(method, args...)
	if err != nil {
		return nil, err
	}

	if val == nil {
		return nil, nil
	}
	return val.Export(), nil
}
