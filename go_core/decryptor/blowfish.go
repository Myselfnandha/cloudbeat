package decryptor

import (
	"crypto/cipher"
	"crypto/md5"
	"encoding/hex"
	"errors"

	"golang.org/x/crypto/blowfish"
)

const (
	DeezerChunkSize = 2048
	DeezerSalt      = "g4el58wc0zvf9na1"
)

var DeezerIV = []byte{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07}

// DeriveDeezerKey calculates the 16-byte Blowfish key for a Deezer track ID.
func DeriveDeezerKey(trackID string) ([]byte, error) {
	if trackID == "" {
		return nil, errors.New("empty track ID")
	}

	hash := md5.Sum([]byte(trackID))
	hexHash := hex.EncodeToString(hash[:]) // 32 hex chars

	key := make([]byte, 16)
	for i := 0; i < 16; i++ {
		key[i] = hexHash[i] ^ hexHash[i+16] ^ DeezerSalt[i]
	}
	return key, nil
}

// DecryptDeezerChunk decrypts a 2048-byte chunk in place if chunkIndex % 3 == 0.
func DecryptDeezerChunk(data []byte, chunkIndex int, trackID string) error {
	if len(data) == 0 {
		return nil
	}

	// Deezer only encrypts every 3rd chunk if it is full 2048 bytes
	if chunkIndex%3 != 0 || len(data) != DeezerChunkSize {
		return nil
	}

	key, err := DeriveDeezerKey(trackID)
	if err != nil {
		return err
	}

	block, err := blowfish.NewCipher(key)
	if err != nil {
		return err
	}

	iv := make([]byte, len(DeezerIV))
	copy(iv, DeezerIV)

	mode := cipher.NewCBCDecrypter(block, iv)
	mode.CryptBlocks(data, data)
	return nil
}
