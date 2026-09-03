```bash
#!/bin/bash

set -euo pipefail

# ============================================================
# CLUSTER-SPECIFIC VARIABLES
# ============================================================

# ------------------------------------------------------------
# Utility paths
# ------------------------------------------------------------

ELASTICSEARCH_CERTUTIL="/path/to/elasticsearch/bin/elasticsearch-certutil"
OPENSSL="/usr/bin/openssl"
UNZIP="/usr/bin/unzip"


# ------------------------------------------------------------
# Cluster
# ------------------------------------------------------------

CLUSTER_NAME="YOUR_CLUSTER_NAME"

# Directory in which all certificate material will be generated
OUTPUT_DIR="/path/to/certificate/output"


# ------------------------------------------------------------
# Certificate Authority
# ------------------------------------------------------------

CA_NAME="${CLUSTER_NAME}-CA"
CA_PASSWORD="YOUR_CA_PASSWORD"


# ------------------------------------------------------------
# PKCS#12
# ------------------------------------------------------------

P12_PASSWORD="YOUR_P12_PASSWORD"


# ------------------------------------------------------------
# Node 1
# ------------------------------------------------------------

NODE1_NAME="YOUR_NODE_1_NAME"
NODE1_DNS="YOUR_NODE_1_DNS"
NODE1_IP="YOUR_NODE_1_IP"


# ------------------------------------------------------------
# Node 2
# ------------------------------------------------------------

NODE2_NAME="YOUR_NODE_2_NAME"
NODE2_DNS="YOUR_NODE_2_DNS"
NODE2_IP="YOUR_NODE_2_IP"


# ------------------------------------------------------------
# Node 3
# ------------------------------------------------------------

NODE3_NAME="YOUR_NODE_3_NAME"
NODE3_DNS="YOUR_NODE_3_DNS"
NODE3_IP="YOUR_NODE_3_IP"


# ============================================================
# DERIVED VARIABLES
# ============================================================

CA_DIR="${OUTPUT_DIR}/ca"
TRANSPORT_DIR="${OUTPUT_DIR}/transport"
HTTP_DIR="${OUTPUT_DIR}/http"
P12_DIR="${OUTPUT_DIR}/p12"

mkdir -p \
    "${CA_DIR}" \
    "${TRANSPORT_DIR}" \
    "${HTTP_DIR}" \
    "${P12_DIR}"


# ============================================================
# 1. GENERATE CA
# ============================================================

echo "Generating CA..."

"${ELASTICSEARCH_CERTUTIL}" ca \
    --silent \
    --pem \
    --out "${CA_DIR}/${CA_NAME}.zip" \
    --pass "${CA_PASSWORD}"

"${UNZIP}" -o \
    "${CA_DIR}/${CA_NAME}.zip" \
    -d "${CA_DIR}"


# ============================================================
# 2. GENERATE TRANSPORT CERTIFICATES
# ============================================================

echo "Generating transport certificates..."

cat > "${OUTPUT_DIR}/transport-instances.yml" <<EOF
instances:

  - name: ${NODE1_NAME}
    dns:
      - ${NODE1_DNS}
    ip:
      - ${NODE1_IP}

  - name: ${NODE2_NAME}
    dns:
      - ${NODE2_DNS}
    ip:
      - ${NODE2_IP}

  - name: ${NODE3_NAME}
    dns:
      - ${NODE3_DNS}
    ip:
      - ${NODE3_IP}
EOF

"${ELASTICSEARCH_CERTUTIL}" cert \
    --silent \
    --pem \
    --in "${OUTPUT_DIR}/transport-instances.yml" \
    --ca-cert "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    --ca-key "${CA_DIR}/${CA_NAME}/ca/ca.key" \
    --out "${TRANSPORT_DIR}/transport-certificates.zip"

"${UNZIP}" -o \
    "${TRANSPORT_DIR}/transport-certificates.zip" \
    -d "${TRANSPORT_DIR}"


# ============================================================
# 3. GENERATE HTTP CERTIFICATES
# ============================================================

echo "Generating HTTP certificates..."

cat > "${OUTPUT_DIR}/http-instances.yml" <<EOF
instances:

  - name: ${NODE1_NAME}-http
    dns:
      - ${NODE1_DNS}
    ip:
      - ${NODE1_IP}

  - name: ${NODE2_NAME}-http
    dns:
      - ${NODE2_DNS}
    ip:
      - ${NODE2_IP}

  - name: ${NODE3_NAME}-http
    dns:
      - ${NODE3_DNS}
    ip:
      - ${NODE3_IP}
EOF

"${ELASTICSEARCH_CERTUTIL}" cert \
    --silent \
    --pem \
    --in "${OUTPUT_DIR}/http-instances.yml" \
    --ca-cert "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    --ca-key "${CA_DIR}/${CA_NAME}/ca/ca.key" \
    --out "${HTTP_DIR}/http-certificates.zip"

"${UNZIP}" -o \
    "${HTTP_DIR}/http-certificates.zip" \
    -d "${HTTP_DIR}"


# ============================================================
# 4. CREATE TRANSPORT PKCS#12 FILES
# ============================================================

echo "Creating transport PKCS#12 files..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE1_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE1_NAME}/${NODE1_NAME}.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE1_NAME}-transport"

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE2_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE2_NAME}/${NODE2_NAME}.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE2_NAME}-transport"

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE3_NAME}-transport.p12" \
    -inkey "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.key" \
    -in "${TRANSPORT_DIR}/${NODE3_NAME}/${NODE3_NAME}.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE3_NAME}-transport"


# ============================================================
# 5. CREATE HTTP PKCS#12 FILES
# ============================================================

echo "Creating HTTP PKCS#12 files..."

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE1_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE1_NAME}-http/${NODE1_NAME}-http.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE1_NAME}-http"

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE2_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE2_NAME}-http/${NODE2_NAME}-http.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE2_NAME}-http"

"${OPENSSL}" pkcs12 -export \
    -out "${P12_DIR}/${NODE3_NAME}-http.p12" \
    -inkey "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.key" \
    -in "${HTTP_DIR}/${NODE3_NAME}-http/${NODE3_NAME}-http.crt" \
    -certfile "${CA_DIR}/${CA_NAME}/ca/ca.crt" \
    -passout "pass:${P12_PASSWORD}" \
    -name "${NODE3_NAME}-http"


# ============================================================
# COMPLETE
# ============================================================

echo
echo "============================================================"
echo "Certificate generation complete."
echo "============================================================"
echo
echo "CA:"
echo "  ${CA_DIR}"
echo
echo "Transport certificates:"
echo "  ${TRANSPORT_DIR}"
echo
echo "HTTP certificates:"
echo "  ${HTTP_DIR}"
echo
echo "PKCS#12 files:"
echo "  ${P12_DIR}"
echo
```
