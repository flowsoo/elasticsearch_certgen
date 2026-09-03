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


# ------------------------------------------------------------
# PKCS#12
# ------------------------------------------------------------

TRANSPORT_P12_PASSWORD="YOUR_TRANSPORT_P12_PASSWORD"
HTTP_P12_PASSWORD="YOUR_HTTP_P12_PASSWORD"


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
# PRE-FLIGHT CHECKS
# ============================================================

# Fail fast (with a clear message) instead of failing halfway through
# with a confusing "no such file or directory" error.
#
# Deliberately avoids bash's ${!var} indirect-expansion trick: if this
# script is ever sourced from a non-bash interactive shell (e.g. zsh,
# the macOS default), the shebang is bypassed and ${!var} does not
# mean the same thing there \u2014 it can error out instead of expanding.
# Plain, explicit checks work the same everywhere.

check_placeholder() {
    local name="$1"
    local value="$2"
    if [[ "${value}" == YOUR_* ]]; then
        echo "ERROR: ${name} still has its placeholder value ('${value}')." >&2
        echo "Edit the variables at the top of this script before running it." >&2
        exit 1
    fi
}

check_placeholder "CLUSTER_NAME"          "${CLUSTER_NAME}"
check_placeholder "OUTPUT_DIR"            "${OUTPUT_DIR}"
check_placeholder "TRANSPORT_P12_PASSWORD" "${TRANSPORT_P12_PASSWORD}"
check_placeholder "HTTP_P12_PASSWORD"     "${HTTP_P12_PASSWORD}"
check_placeholder "NODE1_NAME"            "${NODE1_NAME}"
check_placeholder "NODE1_DNS"             "${NODE1_DNS}"
check_placeholder "NODE1_IP"              "${NODE1_IP}"
check_placeholder "NODE2_NAME"            "${NODE2_NAME}"
check_placeholder "NODE2_DNS"             "${NODE2_DNS}"
check_placeholder "NODE2_IP"              "${NODE2_IP}"
check_placeholder "NODE3_NAME"            "${NODE3_NAME}"
check_placeholder "NODE3_DNS"             "${NODE3_DNS}"
check_placeholder "NODE3_IP"              "${NODE3_IP}"

for tool in "${ELASTICSEARCH_CERTUTIL}" "${OPENSSL}" "${UNZIP}"; do
    if [[ ! -x "${tool}" ]]; then
        echo "ERROR: required tool not found or not executable: ${tool}" >&2
        exit 1
    fi
done


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
    --out "${CA_DIR}/${CA_NAME}.zip"

"${UNZIP}" -o \
    "${CA_DIR}/${CA_NAME}.zip" \
    -d "${CA_DIR}"

# elasticsearch-certutil's --pem CA zip always extracts to a top-level
# folder literally named "ca/" (ca/ca.crt, ca/ca.key) \u2014 it ignores
# CA_NAME for the folder name (CA_NAME only affects the zip filename
# and the CA's CN). Rename it to CA_NAME here so the variable stays
# meaningful for the rest of the script and CA_DIR isn't ambiguous if
# you ever generate more than one CA in the same OUTPUT_DIR.
mv "${CA_DIR}/ca" "${CA_DIR}/${CA_NAME}"

CA_CERT="${CA_DIR}/${CA_NAME}/ca.crt"
CA_KEY="${CA_DIR}/${CA_NAME}/ca.key"

if [[ ! -f "${CA_CERT}" || ! -f "${CA_KEY}" ]]; then
    echo "ERROR: expected CA files not found at ${CA_CERT} / ${CA_KEY}" >&2
    exit 1
fi


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
    --ca-cert "${CA_CERT}" \
    --ca-key "${CA_KEY}" \
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
    --ca-cert "${CA_CERT}" \
    --ca-key "${CA_KEY}" \
    --out "${HTTP_DIR}/http-certificates.zip"

"${UNZIP}" -o \
    "${HTTP_DIR}/http-certificates.zip" \
    -d "${HTTP_DIR}"


# ============================================================
# 4. CREATE TRANSPORT PKCS#12 FILES
# ============================================================

echo "Creating transport PKCS#12 files..."

for NODE_NAME in "${NODE1_NAME}" "${NODE2_NAME}" "${NODE3_NAME}"; do
    "${OPENSSL}" pkcs12 -export \
        -out "${P12_DIR}/${NODE_NAME}-transport.p12" \
        -inkey "${TRANSPORT_DIR}/${NODE_NAME}/${NODE_NAME}.key" \
        -in "${TRANSPORT_DIR}/${NODE_NAME}/${NODE_NAME}.crt" \
        -certfile "${CA_CERT}" \
        -passout "pass:${TRANSPORT_P12_PASSWORD}" \
        -name "${NODE_NAME}-transport"
done


# ============================================================
# 5. CREATE HTTP PKCS#12 FILES
# ============================================================

echo "Creating HTTP PKCS#12 files..."

for NODE_NAME in "${NODE1_NAME}" "${NODE2_NAME}" "${NODE3_NAME}"; do
    "${OPENSSL}" pkcs12 -export \
        -out "${P12_DIR}/${NODE_NAME}-http.p12" \
        -inkey "${HTTP_DIR}/${NODE_NAME}-http/${NODE_NAME}-http.key" \
        -in "${HTTP_DIR}/${NODE_NAME}-http/${NODE_NAME}-http.crt" \
        -certfile "${CA_CERT}" \
        -passout "pass:${HTTP_P12_PASSWORD}" \
        -name "${NODE_NAME}-http"
done


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
