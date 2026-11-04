#!/bin/bash
set -e

# Question 15: TLS material for an HTTPS listener
# q11 runs first in glob order and does the authoritative Gateway API probe; if it
# found nothing there is no point paying the timeout again here.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from question 11's setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
    for crd in gateways httproutes; do
        for _ in $(seq 1 12); do
            if kubectl get "crd/${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
                break
            fi
            sleep 5
        done
        kubectl wait --for=condition=established --timeout=30s "crd/${crd}.gateway.networking.k8s.io" \
            || { GATEWAY_API_OK=no; echo "WARNING: CRD ${crd}.gateway.networking.k8s.io is not established"; }
    done
fi

kubectl create namespace edge-tls --dry-run=client -o yaml | kubectl apply -f -

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute secure-route -n edge-tls --ignore-not-found=true
    kubectl delete gateway tls-gw -n edge-tls --ignore-not-found=true
fi

# A fixed self signed certificate for secure.helioscale.io, so the Secret is
# identical on every attempt and no certificate tooling is required at exam time.
CERT_DIR=$(mktemp -d)
trap 'rm -rf "$CERT_DIR"' EXIT

cat > "$CERT_DIR/tls.crt" <<EOF
-----BEGIN CERTIFICATE-----
MIIDajCCAlKgAwIBAgIUQq0rQ+sbiRFY8FpA7awmpFSNYLUwDQYJKoZIhvcNAQEL
BQAwNDEdMBsGA1UEAwwUc2VjdXJlLmhlbGlvc2NhbGUuaW8xEzARBgNVBAoMCkhl
bGlvc2NhbGUwHhcNMjYwODE3MTQ0MzIyWhcNMzYwODE0MTQ0MzIyWjA0MR0wGwYD
VQQDDBRzZWN1cmUuaGVsaW9zY2FsZS5pbzETMBEGA1UECgwKSGVsaW9zY2FsZTCC
ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALCgiVzSZvIVvAXarkOGukBV
SBJBIJn/qoX8AWYevI/oSSJidHW9fjbUErM0izpTRZcfXnb9qTNrlpsZaWdwZ4DG
V/jBoZqlVYlA0cLE7eDvC3clpUcnRU6lmvNvgbcBviOqkIhrDMp3OauWac/Hf1Zu
kcJhjxwAepSI9R0icLyRNr7KzNmL3i7jIruohuHq4YMulSsxjWlysYvrjLtPEoHL
Uq/3LFjE7PQa/bDSTtJ3QAvUk+GEVif2Hrjpt+k/MZNljqM+aipb/y4D5RdHNuDI
95DLsmrKbude8C16HNKixFdNJA5LuiOy4qhgNJbaiNd3774ZOWQqJqCv1HQSrxEC
AwEAAaN0MHIwHQYDVR0OBBYEFLDyliGqWXJKzDuSqoKHxhJ1R0omMB8GA1UdIwQY
MBaAFLDyliGqWXJKzDuSqoKHxhJ1R0omMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0R
BBgwFoIUc2VjdXJlLmhlbGlvc2NhbGUuaW8wDQYJKoZIhvcNAQELBQADggEBADvG
k62r3OvQeL1NkfkzBcHRbZ3uQZEOEZPkGx0LKdNDyoBfSuVU8ln8seUFOiS4zwK9
xCHeIQQRDTFvnOB563ubXa4jMyf60eMaA4phsDcB1VHhWUqnNvKyLwl6Zprw/Xvf
fwls4Ke6rHYRo/Jl2bQT+Xpl1ZWw+iIuiLauJyUFxV26nurle//kLr9x6WpgYFXA
z4BOqvL0wlurKwYFZfI/Y1A/74LRmyEp8YY90UvtIkVrtGYnXKXPnVrE8JnTY5v/
CWFDRah0O9Co4ezGBqva+3ETOuT5SiwbhHfB5OhNJ6ZRu1cBqnuj7AJz6ZJum4xn
n4gUm3cglmx/6ueuEAU=
-----END CERTIFICATE-----
EOF

cat > "$CERT_DIR/tls.key" <<EOF
-----BEGIN PRIVATE KEY-----
MIIEuwIBADANBgkqhkiG9w0BAQEFAASCBKUwggShAgEAAoIBAQCwoIlc0mbyFbwF
2q5DhrpAVUgSQSCZ/6qF/AFmHryP6EkiYnR1vX421BKzNIs6U0WXH152/akza5ab
GWlncGeAxlf4waGapVWJQNHCxO3g7wt3JaVHJ0VOpZrzb4G3Ab4jqpCIawzKdzmr
lmnPx39WbpHCYY8cAHqUiPUdInC8kTa+yszZi94u4yK7qIbh6uGDLpUrMY1pcrGL
64y7TxKBy1Kv9yxYxOz0Gv2w0k7Sd0AL1JPhhFYn9h646bfpPzGTZY6jPmoqW/8u
A+UXRzbgyPeQy7Jqym7nXvAtehzSosRXTSQOS7ojsuKoYDSW2ojXd+++GTlkKiag
r9R0Eq8RAgMBAAECggEACOHDYCpcbuc7S0TetBqXgLPiw4UIfkLMpAXMjc9IRo+B
wS7kq4vZ4VvzJmI81hppF3TGXulzYFiUSQks5omEF7lICmq1e7DwujQxcb/nzmkQ
hIjqF/sYXlOv+3arnGfqbdS36+qmLzalOcTlXhBEJ2gfM4BaBMIPzl3zJYHqQjEq
ePh1EyQpRtklCeMrO9+RftvXlhoAsNLESZ824QtnHkOOEKEMSC8H8J2L0yC6tuQa
sOq7KqwAwWtNob8IVp5Tmn3NSEeb5NCb8UEQhve33FTLdygiDO1CvX5IEb2fGYKa
z8nbBEA2Pa41BbQ5RFTKNz0r407ANtqFZC0xT+HN2QKBgQDvbAGYI4V8qFUPCgkP
kKi6/EVkDrmJcXsDhWRQ4FFk3Q/XDSSOGzIeUO4XINROReovFAcOu4gQIjWGbEB7
5jHSnK0Ze3qaK/cdUa4ffHHsgDcUWJ9E+rIztejJFY3LWyJK7N8hGE3zZX0GxZk9
kQg2YDMMdCqAOV/Wr+Qkbq3UHwKBgQC8223p4/I2ySPZ+cFfF/427kae/DeaugWD
fTraBYGYokGn/f5zo4LToueTlGR1OMe7KWg4Qtp7G1e1VQeno/PAJ5yKroQSJMJ5
QLY0V4s2nJyXkEMUBjmA++Brwp/JETSiXmpQSkll1rDxDXdYi3zdCyfvRr6hXajk
ITDtjYaWzwKBgQCyuTNveIS7C4WDVoBxCBGMk6jRClTiDr4/YKID5Y+c9ZBPflYd
ZpvBGbTBuxYA4BvyzMZ/7umg8Yh3MfPpCWuDxsVI0m4xDETJtCGBC4qXexair40l
FudTxqVhBh/0/7DXsX7W26fE26u7FGJSHSO+Q42X7FeVpD6wqlhqAdztDQKBgCtg
xz06sy6sQoTVnfnGnAhn8GaiDe+HHK8X+4WKUDsLwcLhTymme+06dLBsHCrkkNPH
bf3GNUKjhCDNWAXEXb9cGdOsw/8a3GRXXcJl/T7c+AbEBvQ5fcnHkMOPn33iatGE
mCy682Llzhx/+FKpL1PiNRj7iduslJdZnFBj+m73An8TDWQckpoOqcyMzYsCxVdB
SD/3y045aM53uN73A/o0c8+MGUN3DncJkYnvKdiH1djhW2PJVQYHQzqvOMFSwfh0
2FKhubfb8Aew6HMUMna5l4gy1ylROITuj3UyMGbuu9pmlHRs21EnlZSnVP52BXEK
GRiZmybV5jGiZN6vBMtX
-----END PRIVATE KEY-----
EOF

kubectl create secret tls helioscale-tls -n edge-tls \
    --cert="$CERT_DIR/tls.crt" --key="$CERT_DIR/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: edge-tls
spec:
  replicas: 2
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: secure-svc
  namespace: edge-tls
spec:
  type: ClusterIP
  selector:
    app: secure-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF

kubectl rollout status deployment/secure-app -n edge-tls --timeout=180s || true

echo "Setup completed for Question 15"
