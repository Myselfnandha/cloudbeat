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

//export CloudBeat_FreeString
func CloudBeat_FreeString(str *C.char) {
	if str != nil {
		C.free(unsafe.Pointer(str))
	}
}
