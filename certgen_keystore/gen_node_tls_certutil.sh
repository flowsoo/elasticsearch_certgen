#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# VARIABLES \u2014 CHANGE THESE
###############################################################################

# Elasticsearch installation directory
ELASTIC_HOME="/usr/share/elasticsearch"

# Working directory for generated CA/cert/p12 files.
# On node1, the CA gets created here.
# On node2/node3, copy elastic-stack-ca.p12 into this same directory BEFORE
# running, so the script reuses the existing CA instead of creating a new one.
WORK_DIR="/usr/share/elasticsearch/elastic-tls"

# Current Elasticsearch node
NODE_NAME="node1"
NODE_IP="10.0.0.11"
NODE_DNS="node1.example.com"

# Passwords (plaintext \u2014 fine for this use case)
CA_PASSWORD="CHANGE_ME_CA_PASSWORD"
NODE_P12_PASSWORD="CHANGE_ME_NODE_P12_PASSWORD"

# CA validity (days). Only used the first time the CA is created.
CA_DAYS=3650

# Node certificate validity (days)
NODE_CERT_DAYS=825

###############################################################################
# DO NOT CHANGE BELOW THIS LINE
###############################################################################

CA_P12="${WORK_DIR}/elastic-stack-ca.p12"
NODE_P12="${WORK_DIR}/${NODE_NAME}.p12"

CERTUTIL="${ELASTIC_HOME}/bin/elasticsearch-certutil"
KEYTOOL="${ELASTIC_HOME}/jdk/bin/keytool"

mkdir -p "${WORK_DIR}"

echo
echo "============================================================"
echo "Elasticsearch transport TLS preparation (certutil)"
echo "============================================================"
echo "Node name : ${NODE_NAME}"
echo "Node IP   : ${NODE_IP}"
echo "Node DNS  : ${NODE_DNS}"
echo "Work dir  : ${WORK_DIR}"
echo "============================================================"
echo

###############################################################################
# A1 \u2014 CREATE OR REUSE CA
###############################################################################

if [[ ! -f "${CA_P12}" ]]; then

    echo "[A1] Creating CA..."

    "${CERTUTIL}" ca \
        --out "${CA_P12}" \
        --days "${CA_DAYS}" \
        --pass "${CA_PASSWORD}" \
        --silent

else

    echo "[A1] CA already exists in ${WORK_DIR} \u2014 reusing:"
    echo "      ${CA_P12}"
    echo "      (copy elastic-stack-ca.p12 here from node1 before running on other nodes)"

fi

###############################################################################
# A2 \u2014 CREATE NODE CERTIFICATE + P12 (bundles CA as trustedCertEntry automatically)
###############################################################################

echo "[A2] Creating node certificate and p12..."

"${CERTUTIL}" cert \
    --ca "${CA_P12}" \
    --ca-pass "${CA_PASSWORD}" \
    --name "${NODE_NAME}" \
    --dns "${NODE_DNS},${NODE_NAME}" \
    --ip "${NODE_IP}" \
    --days "${NODE_CERT_DAYS}" \
    --pass "${NODE_P12_PASSWORD}" \
    --out "${NODE_P12}" \
    --silent

###############################################################################
# A3 \u2014 VERIFY P12 CONTENTS
###############################################################################

echo "[A3] Verifying p12 contents..."

P12_LISTING="$("${KEYTOOL}" -list -keystore "${NODE_P12}" -storetype PKCS12 -storepass "${NODE_P12_PASSWORD}")"

if ! grep -q "PrivateKeyEntry" <<< "${P12_LISTING}"; then
    echo "ERROR: ${NODE_P12} is missing the instance PrivateKeyEntry." >&2
    exit 1
fi

if ! grep -q "trustedCertEntry" <<< "${P12_LISTING}"; then
    echo "ERROR: ${NODE_P12} is missing the CA trustedCertEntry \u2014 truststore will be empty." >&2
    exit 1
fi

echo "[A3] Verified: p12 contains both a PrivateKeyEntry and a trustedCertEntry."

###############################################################################
# A4 \u2014 ELASTICSEARCH SECURE KEYSTORE
###############################################################################

echo "[A4] Adding transport keystore password..."

printf '%s\n' "${NODE_P12_PASSWORD}" | \
    "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
        -x \
        xpack.security.transport.ssl.keystore.secure_password

echo "[A4] Adding transport truststore password..."

printf '%s\n' "${NODE_P12_PASSWORD}" | \
    "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
        -x \
        xpack.security.transport.ssl.truststore.secure_password

###############################################################################
# COMPLETE
###############################################################################

echo
echo "============================================================"
echo "PREPARATION COMPLETE"
echo "============================================================"
echo
echo "Generated:"
echo "  CA p12   : ${CA_P12}"
echo "  Node P12 : ${NODE_P12}"
echo
echo "P12 structure (verified):"
echo "  ${NODE_NAME} -> PrivateKeyEntry"
echo "  ca           -> trustedCertEntry"
echo
echo "Next steps:"
echo "  1. Copy ${NODE_P12} to certs/node1.p12 in your ES config dir (adjust name per node)."
echo "  2. If this was node1, copy ${CA_P12} to WORK_DIR on node2/node3"
echo "     before running this script there, so all nodes share one CA."
echo "  3. Restart Elasticsearch on this node."
echo
echo "A1-A4 completed."
echo "============================================================"
