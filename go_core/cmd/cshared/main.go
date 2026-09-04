package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/hex"
	"encoding/json"
	"time"
	"unsafe"

	"cloudbeat/go_core/decryptor"
	"cloudbeat/go_core/extensions"
	"cloudbeat/go_core/signer"
)

func main() {}

//export CloudBeat_Init
func CloudBeat_Init(cacheDir *C.char) C.int {
	return 1
}

//export CloudBeat_SignZarz
func CloudBeat_SignZarz(sessionId, sessionSecret, method, path, body, appVersion *C.char) *C.char {
	goSessionId := C.GoString(sessionId)
	goSessionSecret := C.GoString(sessionSecret)
	goMethod := C.GoString(method)
	goPath := C.GoString(path)
	goBody := C.GoString(body)
	goAppVersion := C.GoString(appVersion)

	headers, err := signer.SignZarzRequest(
		goSessionId,
		goSessionSecret,
		goMethod,
		goPath,
		goBody,
		goAppVersion,
		time.Now(),
	)
	if err != nil {
		return C.CString(`{"error": "` + err.Error() + `"}`)
	}

	jsonBytes, err := json.Marshal(headers)
	if err != nil {
		return C.CString(`{"error": "` + err.Error() + `"}`)
	}

	return C.CString(string(jsonBytes))
}

//export CloudBeat_DeriveDeezerKey
func CloudBeat_DeriveDeezerKey(trackId *C.char) *C.char {
	goTrackId := C.GoString(trackId)
	key, err := decryptor.DeriveDeezerKey(goTrackId)
	if err != nil {
		return C.CString("")
	}
	return C.CString(hex.EncodeToString(key))
}

//export CloudBeat_DecryptDeezerChunk
func CloudBeat_DecryptDeezerChunk(chunkData *C.uchar, chunkLen C.int, chunkIndex C.int, trackId *C.char) C.int {
	if chunkData == nil || chunkLen <= 0 {
		return 0
	}

	goTrackId := C.GoString(trackId)
	length := int(chunkLen)

	// Create a Go slice backed by the C array pointer without copying
	slice := unsafe.Slice((*byte)(unsafe.Pointer(chunkData)), length)

	err := decryptor.DecryptDeezerChunk(slice, int(chunkIndex), goTrackId)
	if err != nil {
		return -1
	}
	return 1
}

//export CloudBeat_LoadExtension
func CloudBeat_LoadExtension(name, manifestJSON, jsSource *C.char) C.int {
	goName := C.GoString(name)
	goManifest := C.GoString(manifestJSON)
	goJs := C.GoString(jsSource)

	err := extensions.LoadExtension(goName, goManifest, goJs)
	if err != nil {
		return 0
	}
	return 1
}

//export CloudBeat_ExecuteCommand
func CloudBeat_ExecuteCommand(jsonRequest *C.char) *C.char {
	goJson := C.GoString(jsonRequest)
	
	var req struct {
		Extension string        `json:"extension"`
		Method    string        `json:"method"`
		Args      []interface{} `json:"args"`
	}
	
	if err := json.Unmarshal([]byte(goJson), &req); err != nil {
		return C.CString(`{"error": "` + err.Error() + `"}`)
	}
	
	res, err := extensions.ExecuteCommand(req.Extension, req.Method, req.Args)
	if err != nil {
		return C.CString(`{"error": "` + err.Error() + `"}`)
	}
	
	resBytes, err := json.Marshal(res)
	if err != nil {
		return C.CString(`{"error": "` + err.Error() + `"}`)
	}
	
	return C.CString(string(resBytes))
}

//export CloudBeat_FreeString
func CloudBeat_FreeString(str *C.char) {
	if str != nil {
		C.free(unsafe.Pointer(str))
	}
}
