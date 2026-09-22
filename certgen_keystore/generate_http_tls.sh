#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# VARIABLES \u2014 CHANGE THESE
###############################################################################

# Elasticsearch installation directory
ELASTIC_HOME="/usr/share/elasticsearch"

# Working directory for generated CA/cert/key/p12 files.
# Should match the WORK_DIR used by the transport script, so this reuses the
# same CA (ca.key + ca.crt) rather than creating a second one.
WORK_DIR="/usr/share/elasticsearch/elastic-tls"

# Current Elasticsearch node
NODE_NAME="node1"
NODE_IP="10.0.0.11"
NODE_DNS="node1.example.com"

# Extra SANs clients might use to reach this node over HTTPS
# (e.g. a load balancer hostname, a shortname, an alternate IP).
# Leave empty ("") if not needed. Format: "DNS:foo.example.com,IP:10.0.0.99"
EXTRA_SANS=""

# Passwords (plaintext \u2014 fine for this use case)
CA_PASSWORD="CHANGE_ME_CA_PASSWORD"
HTTP_KEY_PASSWORD="CHANGE_ME_HTTP_KEY_PASSWORD"
HTTP_P12_PASSWORD="CHANGE_ME_HTTP_P12_PASSWORD"

# Node certificate validity
HTTP_CERT_DAYS=825

# Whether to enable HTTP client-cert (mutual TLS) support.
# If "true", the CA is also added to http.p12 as a trustedCertEntry, and you
# should also set xpack.security.http.ssl.client_authentication: required
# and register the truststore password in A4 (uncomment the block below).
# If "false" (default), only the keystore is needed for standard HTTPS.
ENABLE_CLIENT_AUTH="false"

###############################################################################
# DO NOT CHANGE BELOW THIS LINE
###############################################################################

CA_KEY="${WORK_DIR}/ca.key"
CA_CERT="${WORK_DIR}/ca.crt"

HTTP_KEY="${WORK_DIR}/${NODE_NAME}-http.key"
HTTP_CSR="${WORK_DIR}/${NODE_NAME}-http.csr"
HTTP_CERT="${WORK_DIR}/${NODE_NAME}-http.crt"
HTTP_EXT="${WORK_DIR}/${NODE_NAME}-http-ext.cnf"
HTTP_P12="${WORK_DIR}/http.p12"

KEYTOOL="${ELASTIC_HOME}/jdk/bin/keytool"

if [[ ! -f "${CA_KEY}" || ! -f "${CA_CERT}" ]]; then
    echo "ERROR: CA not found at ${CA_KEY} / ${CA_CERT}." >&2
    echo "Run the transport cert script first (or copy ca.key + ca.crt into ${WORK_DIR})." >&2
    exit 1
fi

mkdir -p "${WORK_DIR}"

SAN_LIST="DNS:${NODE_DNS},DNS:${NODE_NAME},IP:${NODE_IP}"
if [[ -n "${EXTRA_SANS}" ]]; then
    SAN_LIST="${SAN_LIST},${EXTRA_SANS}"
fi

echo
echo "============================================================"
echo "Elasticsearch HTTP TLS preparation"
echo "============================================================"
echo "Node name       : ${NODE_NAME}"
echo "Node IP         : ${NODE_IP}"
echo "Node DNS        : ${NODE_DNS}"
echo "SANs            : ${SAN_LIST}"
echo "Work dir        : ${WORK_DIR}"
echo "Client auth     : ${ENABLE_CLIENT_AUTH}"
echo "============================================================"
echo

###############################################################################
# B1 \u2014 CREATE HTTP PRIVATE KEY AND CERTIFICATE
###############################################################################

echo "[B1] Creating HTTP private key..."

openssl genrsa \
    -aes256 \
    -passout "pass:${HTTP_KEY_PASSWORD}" \
    -out "${HTTP_KEY}" \
    4096

echo "[B1] Creating certificate signing request..."

openssl req \
    -new \
    -sha256 \
    -key "${HTTP_KEY}" \
    -passin "pass:${HTTP_KEY_PASSWORD}" \
    -out "${HTTP_CSR}" \
    -subj "/CN=${NODE_NAME}"

echo "[B1] Creating certificate extensions..."

cat > "${HTTP_EXT}" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=${SAN_LIST}
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF

echo "[B1] Signing HTTP certificate with CA..."

openssl x509 \
    -req \
    -sha256 \
    -in "${HTTP_CSR}" \
    -CA "${CA_CERT}" \
    -CAkey "${CA_KEY}" \
    -passin "pass:${CA_PASSWORD}" \
    -CAcreateserial \
    -out "${HTTP_CERT}" \
    -days "${HTTP_CERT_DAYS}" \
    -extfile "${HTTP_EXT}"

###############################################################################
# B2 \u2014 CREATE P12
###############################################################################

echo "[B2] Creating PKCS#12 file..."

openssl pkcs12 \
    -export \
    -out "${HTTP_P12}" \
    -inkey "${HTTP_KEY}" \
    -passin "pass:${HTTP_KEY_PASSWORD}" \
    -in "${HTTP_CERT}" \
    -name instance \
    -passout "pass:${HTTP_P12_PASSWORD}"

if [[ "${ENABLE_CLIENT_AUTH}" == "true" ]]; then

    echo "[B2] Client auth enabled \u2014 adding CA as trustedCertEntry..."

    "${KEYTOOL}" \
        -importcert \
        -alias ca \
        -file "${CA_CERT}" \
        -keystore "${HTTP_P12}" \
        -storetype PKCS12 \
        -storepass "${HTTP_P12_PASSWORD}" \
        -noprompt

else
    echo "[B2] Client auth disabled \u2014 skipping CA import (keystore-only, as HTTP normally needs)."
fi

echo "[B2] Verifying p12 contents..."

P12_LISTING="$("${KEYTOOL}" -list -keystore "${HTTP_P12}" -storetype PKCS12 -storepass "${HTTP_P12_PASSWORD}")"

if ! grep -q "PrivateKeyEntry" <<< "${P12_LISTING}"; then
    echo "ERROR: ${HTTP_P12} is missing the instance PrivateKeyEntry." >&2
    exit 1
fi

if [[ "${ENABLE_CLIENT_AUTH}" == "true" ]] && ! grep -q "trustedCertEntry" <<< "${P12_LISTING}"; then
    echo "ERROR: ${HTTP_P12} is missing the CA trustedCertEntry \u2014 required for client auth." >&2
    exit 1
fi

echo "[B2] Verified: p12 structure OK."

###############################################################################
# B3 \u2014 ELASTICSEARCH SECURE KEYSTORE
###############################################################################

echo "[B3] Adding HTTP keystore password..."

printf '%s\n' "${HTTP_P12_PASSWORD}" | \
    "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
        -x \
        xpack.security.http.ssl.keystore.secure_password

# Only needed if ENABLE_CLIENT_AUTH="true" AND
# xpack.security.http.ssl.client_authentication is set to "required"/"optional"
# in elasticsearch.yml, with a matching truststore.path configured.
#
# echo "[B3] Adding HTTP truststore password..."
#
# printf '%s\n' "${HTTP_P12_PASSWORD}" | \
#     "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
#         -x \
#         xpack.security.http.ssl.truststore.secure_password

###############################################################################
# COMPLETE
###############################################################################

echo
echo "============================================================"
echo "HTTP TLS PREPARATION COMPLETE"
echo "============================================================"
echo
echo "Generated:"
echo "  HTTP key        : ${HTTP_KEY}"
echo "  HTTP CSR        : ${HTTP_CSR}"
echo "  HTTP certificate: ${HTTP_CERT}"
echo "  HTTP P12        : ${HTTP_P12}"
echo
echo "Next steps:"
echo "  1. Copy ${HTTP_P12} to certs/http.p12 in your ES config dir."
echo "  2. Confirm elasticsearch.yml has:"
echo "       xpack.security.http.ssl.enabled: true"
echo "       xpack.security.http.ssl.keystore.path: certs/http.p12"
echo "  3. Restart Elasticsearch on this node."
echo "  4. Repeat on node2/node3 with their own NODE_NAME/NODE_IP/NODE_DNS,"
echo "     using the same shared CA in WORK_DIR."
echo
echo "B1-B3 completed."
echo "============================================================"
