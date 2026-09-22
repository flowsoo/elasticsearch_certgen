#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# VARIABLES \u2014 CHANGE THESE
###############################################################################

# Elasticsearch installation directory
ELASTIC_HOME="/usr/share/elasticsearch"

# Working directory for generated CA/cert/key/p12 files.
# On node1, this is where the CA gets created.
# On node2/node3, copy ca.key + ca.crt into this same directory BEFORE running,
# so the script reuses the existing CA instead of creating a new one.
WORK_DIR="/usr/share/elasticsearch/elastic-tls"

# Current Elasticsearch node
NODE_NAME="node1"
NODE_IP="10.0.0.11"
NODE_DNS="node1.example.com"

# Passwords (plaintext \u2014 fine for this use case)
CA_PASSWORD="CHANGE_ME_CA_PASSWORD"
NODE_KEY_PASSWORD="CHANGE_ME_NODE_KEY_PASSWORD"
P12_PASSWORD="CHANGE_ME_P12_PASSWORD"

# CA validity
CA_DAYS=3650

# Node certificate validity
NODE_CERT_DAYS=825

###############################################################################
# DO NOT CHANGE BELOW THIS LINE
###############################################################################

CA_KEY="${WORK_DIR}/ca.key"
CA_CERT="${WORK_DIR}/ca.crt"

NODE_KEY="${WORK_DIR}/${NODE_NAME}.key"
NODE_CSR="${WORK_DIR}/${NODE_NAME}.csr"
NODE_CERT="${WORK_DIR}/${NODE_NAME}.crt"
NODE_EXT="${WORK_DIR}/${NODE_NAME}-ext.cnf"
NODE_P12="${WORK_DIR}/${NODE_NAME}.p12"

KEYTOOL="${ELASTIC_HOME}/jdk/bin/keytool"

mkdir -p "${WORK_DIR}"

echo
echo "============================================================"
echo "Elasticsearch TLS preparation"
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

if [[ ! -f "${CA_KEY}" || ! -f "${CA_CERT}" ]]; then

    echo "[A1] Creating CA private key..."

    openssl genrsa \
        -aes256 \
        -passout "pass:${CA_PASSWORD}" \
        -out "${CA_KEY}" \
        4096

    echo "[A1] Creating CA certificate..."

    openssl req \
        -x509 \
        -new \
        -sha256 \
        -key "${CA_KEY}" \
        -passin "pass:${CA_PASSWORD}" \
        -out "${CA_CERT}" \
        -days "${CA_DAYS}" \
        -subj "/CN=Elasticsearch-CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"

else

    echo "[A1] CA already exists in ${WORK_DIR} \u2014 reusing:"
    echo "      ${CA_CERT}"
    echo "      (copy ca.key + ca.crt here from node1 before running on other nodes)"

fi

###############################################################################
# A2 \u2014 CREATE NODE PRIVATE KEY AND CERTIFICATE
###############################################################################

echo "[A2] Creating node private key..."

openssl genrsa \
    -aes256 \
    -passout "pass:${NODE_KEY_PASSWORD}" \
    -out "${NODE_KEY}" \
    4096

echo "[A2] Creating certificate signing request..."

openssl req \
    -new \
    -sha256 \
    -key "${NODE_KEY}" \
    -passin "pass:${NODE_KEY_PASSWORD}" \
    -out "${NODE_CSR}" \
    -subj "/CN=${NODE_NAME}"

echo "[A2] Creating certificate extensions..."

cat > "${NODE_EXT}" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:${NODE_DNS},DNS:${NODE_NAME},IP:${NODE_IP}
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

echo "[A2] Signing node certificate with CA..."

openssl x509 \
    -req \
    -sha256 \
    -in "${NODE_CSR}" \
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -passin "pass:${CA_PASSWORD}" \
    -CAcreateserial \
    -out "${NODE_CERT}" \
    -days "${NODE_CERT_DAYS}" \
    -extfile "${NODE_EXT}"

###############################################################################
# A3 \u2014 CREATE P12 AND ADD CA AS TRUSTED ENTRY
###############################################################################

echo "[A3] Creating PKCS#12 file..."

openssl pkcs12 \
    -export \
    -out "${NODE_P12}" \
    -inkey "${NODE_KEY}" \
    -passin "pass:${NODE_KEY_PASSWORD}" \
    -in "${NODE_CERT}" \
    -name instance \
    -passout "pass:${P12_PASSWORD}"

echo "[A3] Adding CA as trustedCertEntry..."

"${KEYTOOL}" \
    -importcert \
    -alias ca \
    -file "${CA_CERT}" \
    -keystore "${NODE_P12}" \
    -storetype PKCS12 \
    -storepass "${P12_PASSWORD}" \
    -noprompt

echo "[A3] Verifying p12 contents..."

P12_LISTING="$("${KEYTOOL}" -list -keystore "${NODE_P12}" -storetype PKCS12 -storepass "${P12_PASSWORD}")"

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

printf '%s\n' "${P12_PASSWORD}" | \
    "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
        -x \
        xpack.security.transport.ssl.keystore.secure_password

echo "[A4] Adding transport truststore password..."

printf '%s\n' "${P12_PASSWORD}" | \
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
echo "  CA certificate  : ${CA_CERT}"
echo "  Node key        : ${NODE_KEY}"
echo "  Node CSR        : ${NODE_CSR}"
echo "  Node certificate: ${NODE_CERT}"
echo "  Node P12        : ${NODE_P12}"
echo
echo "P12 structure (verified):"
echo "  instance -> PrivateKeyEntry"
echo "  ca       -> trustedCertEntry"
echo
echo "Next steps:"
echo "  1. Copy ${NODE_P12} to certs/node1.p12 in your ES config dir (adjust path per node)."
echo "  2. If this was node1, copy ${CA_KEY} and ${CA_CERT} to WORK_DIR on node2/node3"
echo "     before running this script there, so all nodes share one CA."
echo "  3. Restart Elasticsearch on this node."
echo
echo "A1-A4 completed."
echo "============================================================"
