package extensions

import (
	"archive/zip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/dop251/goja"
)

// Manifest represents the parsed manifest.json from an .sflx package
type Manifest struct {
	Name                    string                 `json:"name"`
	DisplayName             string                 `json:"displayName"`
	Version                 string                 `json:"version"`
	Description             string                 `json:"description"`
	Type                    []string               `json:"type"`
	MinAppVersion           string                 `json:"minAppVersion"`
	RequiredRuntimeFeatures []string               `json:"requiredRuntimeFeatures"`
	Settings                []ExtensionSetting     `json:"settings"`
	SignedSession           map[string]interface{} `json:"signedSession"`
	Permissions             map[string]interface{} `json:"permissions"`
}

type ExtensionSetting struct {
	Key         string      `json:"key"`
	Label       string      `json:"label"`
	Type        string      `json:"type"`
	Default     interface{} `json:"default"`
	Description string      `json:"description"`
}

// Runner encapsulates a Goja VM environment executing a SpotiFLAC .sflx extension
type Runner struct {
	Manifest Manifest
	vm       *goja.Runtime
	script   string
}

// LoadFromSFLX loads an extension from a .sflx zip bundle or directory
func LoadFromSFLX(path string) (*Runner, error) {
	fi, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("extension path not found: %w", err)
	}

	var manifestBytes []byte
	var scriptBytes []byte

	if fi.IsDir() {
		// Load from directory
		mPath := filepath.Join(path, "manifest.json")
		manifestBytes, err = os.ReadFile(mPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read manifest.json: %w", err)
		}

		sPath := filepath.Join(path, "index.js")
		scriptBytes, err = os.ReadFile(sPath)
		if err != nil {
			return nil, fmt.Errorf("failed to read index.js: %w", err)
		}
	} else {
		// Load from zip archive
		zr, err := zip.OpenReader(path)
		if err != nil {
			return nil, fmt.Errorf("failed to open .sflx archive: %w", err)
		}
		defer zr.Close()

		for _, f := range zr.File {
			if f.Name == "manifest.json" {
				rc, err := f.Open()
				if err == nil {
					manifestBytes, _ = io.ReadAll(rc)
					rc.Close()
				}
			} else if f.Name == "index.js" {
				rc, err := f.Open()
				if err == nil {
					scriptBytes, _ = io.ReadAll(rc)
					rc.Close()
				}
			}
		}
	}

	if len(manifestBytes) == 0 {
		return nil, errors.New("manifest.json not found in extension package")
	}
	if len(scriptBytes) == 0 {
		return nil, errors.New("index.js not found in extension package")
	}

	var manifest Manifest
	if err := json.Unmarshal(manifestBytes, &manifest); err != nil {
		return nil, fmt.Errorf("malformed manifest.json: %w", err)
	}

	runner := &Runner{
		Manifest: manifest,
		vm:       goja.New(),
		script:   string(scriptBytes),
	}

	if err := runner.setupEnvironment(); err != nil {
		return nil, err
	}

	return runner, nil
}

// LoadFromSource initializes an extension directly from manifest and JS source strings
func LoadFromSource(manifestJSON, jsSource string) (*Runner, error) {
	var manifest Manifest
	if err := json.Unmarshal([]byte(manifestJSON), &manifest); err != nil {
		return nil, fmt.Errorf("malformed manifest.json: %w", err)
	}

	runner := &Runner{
		Manifest: manifest,
		vm:       goja.New(),
		script:   jsSource,
	}

	if err := runner.setupEnvironment(); err != nil {
		return nil, err
	}

	return runner, nil
}

func (r *Runner) setupEnvironment() error {
	// Standard console logging
	consoleObj := r.vm.NewObject()
	_ = consoleObj.Set("log", func(call goja.FunctionCall) goja.Value {
		return goja.Undefined()
	})
	_ = consoleObj.Set("warn", func(call goja.FunctionCall) goja.Value {
		return goja.Undefined()
	})
	_ = consoleObj.Set("error", func(call goja.FunctionCall) goja.Value {
		return goja.Undefined()
	})
	_ = r.vm.Set("console", consoleObj)

	// Execute index.js
	_, err := r.vm.RunString(r.script)
	if err != nil {
		return fmt.Errorf("failed to evaluate extension script: %w", err)
	}

	return nil
}

// Initialize calls the extension's initialize(settings) function
func (r *Runner) Initialize(settings map[string]interface{}) (bool, error) {
	initVal := r.vm.Get("initialize")
	if initVal == nil || goja.IsUndefined(initVal) {
		return false, errors.New("extension missing initialize function")
	}

	initFn, ok := goja.AssertFunction(initVal)
	if !ok {
		return false, errors.New("initialize is not a function")
	}

	res, err := initFn(goja.Undefined(), r.vm.ToValue(settings))
	if err != nil {
		return false, fmt.Errorf("initialize call failed: %w", err)
	}

	return res.ToBoolean(), nil
}

// CallFunction invokes an arbitrary exported function on the extension
func (r *Runner) CallFunction(name string, args ...interface{}) (goja.Value, error) {
	fnVal := r.vm.Get(name)
	if fnVal == nil || goja.IsUndefined(fnVal) {
		return nil, fmt.Errorf("function '%s' is not defined in extension", name)
	}

	fn, ok := goja.AssertFunction(fnVal)
	if !ok {
		return nil, fmt.Errorf("property '%s' is not a function", name)
	}

	jsArgs := make([]goja.Value, len(args))
	for i, arg := range args {
		jsArgs[i] = r.vm.ToValue(arg)
	}

	return fn(goja.Undefined(), jsArgs...)
}

// Cleanup calls the cleanup function if defined
func (r *Runner) Cleanup() {
	cleanupVal := r.vm.Get("cleanup")
	if cleanupVal != nil && !goja.IsUndefined(cleanupVal) {
		if cleanupFn, ok := goja.AssertFunction(cleanupVal); ok {
			_, _ = cleanupFn(goja.Undefined())
		}
	}
}
