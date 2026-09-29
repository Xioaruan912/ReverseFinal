set -e
D=/root/mmwx/rogue
mkdir -p $D && cd $D
which openssl || (apt-get update -qq && apt-get install -y -qq openssl)
# CA
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout ca.key -out ca.crt \
  -subj "/CN=MMWX-Lab-Rogue-CA" 2>/dev/null
# server key + CSR with SAN
openssl req -newkey rsa:2048 -nodes -keyout srv.key -out srv.csr \
  -subj "/CN=license.miaomiaowux.com" 2>/dev/null
cat > san.cnf <<'CNF'
subjectAltName=DNS:license.miaomiaowux.com,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
CNF
openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 3650 -out srv.crt -extfile san.cnf 2>/dev/null
cat srv.crt srv.key > srv.pem
# trust our CA system-wide (Debian)
cp ca.crt /usr/local/share/ca-certificates/mmwx-lab-rogue-ca.crt
update-ca-certificates 2>&1 | tail -2
ls -la $D
echo "--- verify chain ---"
openssl verify -CAfile ca.crt srv.crt
