```bash
#!/bin/bash

set -euo pipefail

# ============================================================
# ENVIRONMENT-SPECIFIC VARIABLES
# ============================================================

# ------------------------------------------------------------
# Utility paths
# ------------------------------------------------------------

OPENSSL="/usr/bin/openssl"


# ------------------------------------------------------------
# Certificate input/output
# ------------------------------------------------------------

# Directory containing the output from the certificate
# generation script
CERT_DIR="/path/to/certificate/output"

# Directory where the PKCS#12 files will be created
P12_DIR="${CERT_DIR}/p12"


# ------------------------------------------------------------
# Certificate Authority
# ------------------------------------------------------------

CA_NAME="YOUR_CLUSTER_NAME-CA"

CA_CERT="${CERT_DIR}/ca/${CA_NAME}/ca/ca.crt"


# ------------------------------------------------------------
# PKCS#12 passwords
# ------------------------------------------------------------

TRANSPORT_P12_PASSWORD="YOUR_TRANSPORT_P12_PASSWORD"
HTTP_P12_PASSWORD="YOUR_HTTP_P12_PASSWORD"


# ------------------------------------------------------------
# Node 1
# ------------------------------------------------------------

NODE1_NAME="YOUR_NODE_1_NAME"


# ------------------------------------------------------------
# Node 2
# ------------------------------------------------------------

NODE2_NAME="YOUR_NODE_2_NAME"


# ------------------------------------------------------------
# Node 3
# ------------------------------------------------------------

NODE3_NAME="YOUR_NODE_3_NAME"


# ============================================================
# DERIVED VARIABLES
# ============================================================

TRANSPORT_DIR="${CERT_DIR}/transport"
HTTP_DIR="${CERT_DIR}/http"

mkdir -p "${P12_DIR}"


# ============================================================
# VALIDATION
# ============================================================

echo "Validating required files..."

for FILE in \
    "${CA_CERT}" \
    "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.crt" \
    "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.key" \
    "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.crt" \
    "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.key" \
    "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.crt" \
    "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.key" \
    "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.crt" \
    "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.key" \
    "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.crt" \
    "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.key" \
    "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.crt" \
    "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.key"
do
    if [[ ! -f "${FILE}" ]]; then
        echo "ERROR: Required file not found:"
        echo "       ${FILE}"
        exit 1
    fi
done

echo "All required certificate files found."


# ============================================================
# NODE 1 - TRANSPORT P12
# ============================================================

echo "Creating ${NODE1_NAME}-transport.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE1_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${TRANSPORT_P12_PASSWORD}" \
    -name "${NODE1_NAME}-transport"


# ============================================================
# NODE 1 - HTTP P12
# ============================================================

echo "Creating ${NODE1_NAME}-http.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE1_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${HTTP_P12_PASSWORD}" \
    -name "${NODE1_NAME}-http"


# ============================================================
# NODE 2 - TRANSPORT P12
# ============================================================

echo "Creating ${NODE2_NAME}-transport.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE2_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${TRANSPORT_P12_PASSWORD}" \
    -name "${NODE2_NAME}-transport"


# ============================================================
# NODE 2 - HTTP P12
# ============================================================

echo "Creating ${NODE2_NAME}-http.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE2_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${HTTP_P12_PASSWORD}" \
    -name "${NODE2_NAME}-http"


# ============================================================
# NODE 3 - TRANSPORT P12
# ============================================================

echo "Creating ${NODE3_NAME}-transport.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE3_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${TRANSPORT_P12_PASSWORD}" \
    -name "${NODE3_NAME}-transport"


# ============================================================
# NODE 3 - HTTP P12
# ============================================================

echo "Creating ${NODE3_NAME}-http.p12..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE3_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.crt" \
    -certfile "${CA_CERT}" \
    -passout "pass:${HTTP_P12_PASSWORD}" \
    -name "${NODE3_NAME}-http"


# ============================================================
# COMPLETE
# ============================================================

echo
echo "============================================================"
echo "PKCS#12 generation complete."
echo "============================================================"
echo
echo "Generated files:"
echo
echo "  ${P12_DIR}/${NODE1_NAME}-transport.p12"
echo "  ${P12_DIR}/${NODE1_NAME}-http.p12"
echo "  ${P12_DIR}/${NODE2_NAME}-transport.p12"
echo "  ${P12_DIR}/${NODE2_NAME}-http.p12"
echo "  ${P12_DIR}/${NODE3_NAME}-transport.p12"
echo "  ${P12_DIR}/${NODE3_NAME}-http.p12"
echo
```
