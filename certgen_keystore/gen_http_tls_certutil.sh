#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# VARIABLES \u2014 CHANGE THESE
###############################################################################

# Elasticsearch installation directory
ELASTIC_HOME="/usr/share/elasticsearch"

# Working directory for generated CA/cert/p12 files.
# Should match the WORK_DIR used by the transport script, so this reuses the
# same CA (elastic-stack-ca.p12) rather than creating a second one.
WORK_DIR="/usr/share/elasticsearch/elastic-tls"

# Current Elasticsearch node
NODE_NAME="node1"
NODE_IP="10.0.0.11"
NODE_DNS="node1.example.com"

# Extra SANs clients might use to reach this node over HTTPS
# (e.g. a load balancer hostname, a shortname, an alternate IP).
# Leave empty ("") if not needed. Comma-separated, e.g. "lb.example.com,es"
EXTRA_DNS=""
EXTRA_IPS=""

# Passwords (plaintext \u2014 fine for this use case)
CA_PASSWORD="CHANGE_ME_CA_PASSWORD"
HTTP_P12_PASSWORD="CHANGE_ME_HTTP_P12_PASSWORD"

# Node certificate validity (days)
HTTP_CERT_DAYS=825

###############################################################################
# DO NOT CHANGE BELOW THIS LINE
###############################################################################

CA_P12="${WORK_DIR}/elastic-stack-ca.p12"
HTTP_P12="${WORK_DIR}/http.p12"

CERTUTIL="${ELASTIC_HOME}/bin/elasticsearch-certutil"
KEYTOOL="${ELASTIC_HOME}/jdk/bin/keytool"

if [[ ! -f "${CA_P12}" ]]; then
    echo "ERROR: CA not found at ${CA_P12}." >&2
    echo "Run the transport cert script first (or copy elastic-stack-ca.p12 into ${WORK_DIR})." >&2
    exit 1
fi

mkdir -p "${WORK_DIR}"

DNS_LIST="${NODE_DNS},${NODE_NAME}"
if [[ -n "${EXTRA_DNS}" ]]; then
    DNS_LIST="${DNS_LIST},${EXTRA_DNS}"
fi

IP_LIST="${NODE_IP}"
if [[ -n "${EXTRA_IPS}" ]]; then
    IP_LIST="${IP_LIST},${EXTRA_IPS}"
fi

echo
echo "============================================================"
echo "Elasticsearch HTTP TLS preparation (certutil)"
echo "============================================================"
echo "Node name : ${NODE_NAME}"
echo "DNS SANs  : ${DNS_LIST}"
echo "IP SANs   : ${IP_LIST}"
echo "Work dir  : ${WORK_DIR}"
echo "============================================================"
echo

###############################################################################
# B1 \u2014 CREATE HTTP CERTIFICATE + P12 (bundles CA as trustedCertEntry automatically)
###############################################################################

echo "[B1] Creating HTTP certificate and p12..."

"${CERTUTIL}" cert \
    --ca "${CA_P12}" \
    --ca-pass "${CA_PASSWORD}" \
    --name "${NODE_NAME}" \
    --dns "${DNS_LIST}" \
    --ip "${IP_LIST}" \
    --days "${HTTP_CERT_DAYS}" \
    --pass "${HTTP_P12_PASSWORD}" \
    --out "${HTTP_P12}" \
    --silent

###############################################################################
# B2 \u2014 VERIFY P12 CONTENTS
###############################################################################

echo "[B2] Verifying p12 contents..."

P12_LISTING="$("${KEYTOOL}" -list -keystore "${HTTP_P12}" -storetype PKCS12 -storepass "${HTTP_P12_PASSWORD}")"

if ! grep -q "PrivateKeyEntry" <<< "${P12_LISTING}"; then
    echo "ERROR: ${HTTP_P12} is missing the instance PrivateKeyEntry." >&2
    exit 1
fi

echo "[B2] Verified: p12 structure OK."
echo "      (CA trustedCertEntry is also present, bundled automatically by certutil \u2014"
echo "       only needed if you later enable HTTP client authentication.)"

###############################################################################
# B3 \u2014 ELASTICSEARCH SECURE KEYSTORE
###############################################################################

echo "[B3] Adding HTTP keystore password..."

printf '%s\n' "${HTTP_P12_PASSWORD}" | \
    "${ELASTIC_HOME}/bin/elasticsearch-keystore" add \
        -x \
        xpack.security.http.ssl.keystore.secure_password

# Only needed if xpack.security.http.ssl.client_authentication is set to
# "required"/"optional" in elasticsearch.yml, with a matching truststore.path.
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
echo "  HTTP P12 : ${HTTP_P12}"
echo
echo "Next steps:"
echo "  1. Copy ${HTTP_P12} to certs/http.p12 in your ES config dir."
echo "  2. Confirm elasticsearch.yml has:"
echo "       xpack.security.http.ssl.enabled: true"
echo "       xpack.security.http.ssl.keystore.path: certs/http.p12"
echo "  3. Restart Elasticsearch on this node."
echo "  4. Repeat on node2/node3 with their own NODE_NAME/NODE_IP/NODE_DNS,"
echo "     using the same shared CA (elastic-stack-ca.p12) already copied there."
echo
echo "B1-B3 completed."
echo "============================================================"
