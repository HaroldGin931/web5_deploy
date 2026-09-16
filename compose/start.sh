#!/bin/sh
set -eu

deploy_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
env_file="$deploy_dir/.env"
mode=${1:-localhost}

case "$mode" in
  localhost)
    public_host=localhost
    public_scheme=http
    public_origin=http://localhost:18080
    ;;
  http://*|https://*)
    public_origin=${mode%/}
    public_scheme=${public_origin%%://*}
    public_host=${public_origin#*://}
    ;;
  *)
    public_host=$mode
    public_scheme=https
    public_origin=https://$public_host
    ;;
esac

case "$public_host" in
  ''|*/*|*@*|*\?*|*\#*)
    echo "usage: ./start.sh localhost|hostname|http(s)://hostname[:port]" >&2
    exit 2
    ;;
esac

for required_command in docker openssl curl; do
  command -v "$required_command" >/dev/null 2>&1 || {
    echo "missing required command: $required_command" >&2
    exit 1
  }
done

if [ ! -f "$env_file" ]; then
  umask 077
  {
    printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'PDS_JWT_SECRET=%s\n' "$(openssl rand -hex 32)"
    printf 'PDS_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'PDS_ROTATION_KEY=%s\n' "$(openssl rand -hex 32)"
    printf 'APPVIEW_SIGNING_KEY=%s\n' "$(openssl rand -hex 32)"
    printf 'APPVIEW_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'POST_CACHE_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)"
    printf 'RICE_SECRET_KEY_BASE=%s\n' "$(openssl rand -hex 64)"
    printf 'MOCK_ACCOUNT_PASSWORD=Demo%s!\n' "$(openssl rand -hex 6)"
  } >"$env_file"
fi

cert_dir="$deploy_dir/certs"
if [ ! -f "$cert_dir/server.crt" ]; then
  mkdir -p "$cert_dir"
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -subj '/CN=Xiangjian Demo Internal CA' \
    -keyout "$cert_dir/ca.key" \
    -out "$cert_dir/ca.crt" >/dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -sha256 \
    -config "$deploy_dir/tls/openssl.cnf" \
    -keyout "$cert_dir/server.key" \
    -out "$cert_dir/server.csr" >/dev/null 2>&1
  openssl x509 -req -sha256 -days 825 \
    -in "$cert_dir/server.csr" \
    -CA "$cert_dir/ca.crt" \
    -CAkey "$cert_dir/ca.key" \
    -CAcreateserial \
    -extfile "$deploy_dir/tls/openssl.cnf" \
    -extensions server_extensions \
    -out "$cert_dir/server.crt" >/dev/null 2>&1
fi

compose() {
  PUBLIC_HOST="$public_host" \
  PUBLIC_SCHEME="$public_scheme" \
  PUBLIC_ORIGIN="$public_origin" \
    docker compose --env-file "$env_file" -f "$deploy_dir/compose.yml" "$@"
}

wait_http() {
  label=$1
  url=$2
  attempt=1
  while ! curl -fsS --max-time 5 "$url" >/dev/null 2>&1; do
    [ "$attempt" -lt 90 ] || {
      echo "timed out waiting for $label" >&2
      compose ps >&2
      return 1
    }
    attempt=$((attempt + 1))
    sleep 2
  done
  echo "$label is ready"
}

compose config --quiet
compose up -d --build --remove-orphans
# The nginx entrypoint renders templates only when the container starts.
compose up -d --force-recreate --no-deps gateway
wait_http "Rice" "http://127.0.0.1:18080/api/apps"
wait_http "PDS" "http://127.0.0.1:18080/pds/xrpc/com.atproto.server.describeServer"

attempt=1
while ! compose logs post-cache 2>/dev/null | grep -q 'Connected to pds'; do
  [ "$attempt" -lt 90 ] || {
    echo "timed out waiting for Post Cache" >&2
    compose logs --tail=80 post-cache >&2
    exit 1
  }
  attempt=$((attempt + 1))
  sleep 2
done

compose cp "$deploy_dir/seed/demo.exs" rice:/tmp/demo.exs
compose exec -T rice \
  /app/bin/rice rpc 'Code.eval_file("/tmp/demo.exs"); XiangjianDemoSeed.run()'

wait_http "frontend" "http://127.0.0.1:18080/"
. "$env_file"

echo "Demo is ready: $public_origin"
echo "Accounts: alice.uat.test / bob.uat.test / chenxi.uat.test / linlan.uat.test / zhouye.uat.test"
echo "Password: $MOCK_ACCOUNT_PASSWORD"
