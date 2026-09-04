package signer

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"
	"time"
)

type SignedHeaders struct {
	SessionID   string `json:"X-Zarz-Session"`
	Timestamp   string `json:"X-Zarz-Timestamp"`
	Nonce       string `json:"X-Zarz-Nonce"`
	BodyHash    string `json:"X-Zarz-Body-SHA256"`
	AppVersion  string `json:"X-Zarz-App-Version"`
	Platform    string `json:"X-Zarz-Platform"`
	Signature   string `json:"X-Zarz-Signature"`
}

// GenerateRandomNonce returns a 12-char lowercase hex string.
func GenerateRandomNonce() (string, error) {
	b := make([]byte, 6)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// DeriveRollingKey derives a 300-second window HMAC key.
func DeriveRollingKey(sessionSecret, sessionID string, now time.Time) string {
	window := now.Unix() / 300
	rollingInput := fmt.Sprintf("%d:%s", window, sessionID)

	mac := hmac.New(sha256.New, []byte(sessionSecret))
	mac.Write([]byte(rollingInput))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// SignZarzRequest builds the 10-line payload and computes the ZARZ-HMAC-V1 signature.
func SignZarzRequest(sessionID, sessionSecret, method, path, body, appVersion string, now time.Time) (*SignedHeaders, error) {
	nonce, err := GenerateRandomNonce()
	if err != nil {
		return nil, err
	}

	bodyHashBytes := sha256.Sum256([]byte(body))
	bodyHash := hex.EncodeToString(bodyHashBytes[:])

	timestampISO := now.UTC().Format("2006-01-02T15:04:05.000Z")
	platform := "extension"

	rk := DeriveRollingKey(sessionSecret, sessionID, now)

	// 10-line signing payload
	lines := []string{
		"ZARZ-HMAC-V1",
		strings.ToUpper(method),
		path,
		"", // Line 4 empty for query normalization
		bodyHash,
		timestampISO,
		nonce,
		sessionID,
		appVersion,
		platform,
	}
	payload := strings.Join(lines, "\n")

	mac := hmac.New(sha256.New, []byte(rk))
	mac.Write([]byte(payload))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))

	return &SignedHeaders{
		SessionID:  sessionID,
		Timestamp:  timestampISO,
		Nonce:      nonce,
		BodyHash:   bodyHash,
		AppVersion: appVersion,
		Platform:   platform,
		Signature:  sig,
	}, nil
}
