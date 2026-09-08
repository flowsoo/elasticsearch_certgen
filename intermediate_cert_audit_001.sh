#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# USER VARIABLES — CHANGE THESE
# ============================================================

HTTP_P12="/path/to/http.p12"
TRANSPORT_P12="/path/to/transport.p12"
NEW_CA_PEM="/path/to/new-ca.pem"

HTTP_P12_PASSWORD="CHANGE_ME"
TRANSPORT_P12_PASSWORD="CHANGE_ME"

# ============================================================
# DO NOT CHANGE BELOW THIS LINE
# ============================================================

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

FAILED=0

verify_p12() {
    local NAME="$1"
    local P12="$2"
    local PASSWORD="$3"
    local CERT="$TMPDIR/${NAME}.crt"
    local KEY="$TMPDIR/${NAME}.key"

    echo
    echo "============================================================"
    echo "$NAME"
    echo "============================================================"

    # --------------------------------------------------------
    # Check PKCS#12 bundle
    # --------------------------------------------------------

    echo "[1/6] Checking PKCS#12 bundle..."

    if ! openssl pkcs12 \
        -in "$P12" \
        -passin "pass:$PASSWORD" \
        -info \
        -noout \
        >/dev/null 2>&1
    then
        echo "FAIL: Cannot open PKCS#12 bundle"
        FAILED=1
        return
    fi

    echo "OK"

    # --------------------------------------------------------
    # Extract certificate
    # --------------------------------------------------------

    echo "[2/6] Extracting certificate..."

    openssl pkcs12 \
        -in "$P12" \
        -clcerts \
        -nokeys \
        -passin "pass:$PASSWORD" \
        -out "$CERT" \
        >/dev/null 2>&1

    echo "OK"

    # --------------------------------------------------------
    # Display certificate information
    # --------------------------------------------------------

    echo "[3/6] Certificate details:"

    openssl x509 \
        -in "$CERT" \
        -noout \
        -subject \
        -issuer \
        -serial \
        -dates \
        -fingerprint -sha256

    echo
    echo "Subject Alternative Names:"

    openssl x509 \
        -in "$CERT" \
        -noout \
        -ext subjectAltName

    # --------------------------------------------------------
    # Verify certificate against NEW CA
    # --------------------------------------------------------

    echo
    echo "[4/6] Verifying certificate against NEW CA..."

    if openssl verify \
        -CAfile "$NEW_CA_PEM" \
        "$CERT"
    then
        echo "OK: Certificate is signed by the NEW CA"
    else
        echo "FAIL: Certificate is NOT signed by the NEW CA"
        FAILED=1
    fi

    # --------------------------------------------------------
    # Extract private key
    # --------------------------------------------------------

    echo
    echo "[5/6] Checking private key..."

    openssl pkcs12 \
        -in "$P12" \
        -nocerts \
        -nodes \
        -passin "pass:$PASSWORD" \
        -out "$KEY" \
        >/dev/null 2>&1

    if openssl pkey -in "$KEY" -noout >/dev/null 2>&1
    then
        echo "OK: Private key is valid"
    else
        echo "FAIL: Private key is invalid"
        FAILED=1
    fi

    # --------------------------------------------------------
    # Verify certificate/private-key match
    # --------------------------------------------------------

    echo
    echo "[6/6] Verifying certificate/private-key match..."

    CERT_KEY_HASH="$(
        openssl x509 \
            -in "$CERT" \
            -pubkey \
            -noout |
        openssl pkey \
            -pubin \
            -outform DER |
        sha256sum |
        awk '{print $1}'
    )"

    PRIVATE_KEY_HASH="$(
        openssl pkey \
            -in "$KEY" \
            -pubout \
            -outform DER |
        sha256sum |
        awk '{print $1}'
    )"

    if [[ "$CERT_KEY_HASH" == "$PRIVATE_KEY_HASH" ]]
    then
        echo "OK: Certificate matches private key"
    else
        echo "FAIL: Certificate does NOT match private key"
        FAILED=1
    fi
}

# ============================================================
# Basic file checks
# ============================================================

echo "Checking input files..."

for FILE in "$HTTP_P12" "$TRANSPORT_P12" "$NEW_CA_PEM"
do
    if [[ ! -f "$FILE" ]]
    then
        echo "FAIL: File not found: $FILE"
        exit 1
    fi
done

echo "OK: All input files exist"

# ============================================================
# Verify HTTP certificate
# ============================================================

verify_p12 \
    "HTTP CERTIFICATE" \
    "$HTTP_P12" \
    "$HTTP_P12_PASSWORD"

# ============================================================
# Verify TRANSPORT certificate
# ============================================================

verify_p12 \
    "TRANSPORT CERTIFICATE" \
    "$TRANSPORT_P12" \
    "$TRANSPORT_P12_PASSWORD"

# ============================================================
# Final result
# ============================================================

echo
echo "============================================================"

if [[ "$FAILED" -eq 0 ]]
then
    echo "RESULT: ALL CERTIFICATE CHECKS PASSED"
    echo "============================================================"
    exit 0
else
    echo "RESULT: ONE OR MORE CERTIFICATE CHECKS FAILED"
    echo "============================================================"
    exit 1
fi
