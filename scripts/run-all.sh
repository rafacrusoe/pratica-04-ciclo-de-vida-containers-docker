#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/evidencias"
DB_ROOT_PASSWORD="pratica-${GITHUB_RUN_ID:-local}-$(date -u +%s)-$RANDOM"
mkdir -p "$EVIDENCE_DIR"
cd "$ROOT_DIR"

cleanup() {
  docker rm -f webserver db cache web temp >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker version --format 'Cliente={{.Client.Version}} Servidor={{.Server.Version}}' \
  | tee "$EVIDENCE_DIR/00-docker-version.txt"

section() {
  printf '\n### %s ###\n' "$1"
}

wait_for_http() {
  local url="$1"
  for _ in {1..30}; do
    if curl --silent --fail --max-time 2 "$url" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_mysql() {
  for _ in {1..60}; do
    if docker exec db mysqladmin ping -uroot -p"$DB_ROOT_PASSWORD" --silent >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

capture_stats() {
  local label="$1"
  local samples="$2"
  local interval="$3"
  local output="$4"
  printf 'amostra\tcontainer\tcpu\tmemoria\tmemoria_percentual\n' > "$output"
  for ((sample = 1; sample <= samples; sample++)); do
    docker stats --no-stream \
      --format "${sample}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
      db cache web >> "$output"
    printf '%s: amostra %d de %d\n' "$label" "$sample" "$samples"
    if (( sample < samples )); then
      sleep "$interval"
    fi
  done
}

section "Ação 1 - ciclo de vida"
event_start="$(date -u +%s)"

docker create --name webserver -p 80:80 nginx:latest \
  | tee "$EVIDENCE_DIR/01-create.txt"
docker ps -a --filter name=webserver \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | tee "$EVIDENCE_DIR/02-status-created.txt"

docker start webserver | tee "$EVIDENCE_DIR/03-start.txt"
wait_for_http http://localhost:80
curl --silent --show-error --head http://localhost:80 \
  | tee "$EVIDENCE_DIR/04-nginx-running.txt"

docker pause webserver | tee "$EVIDENCE_DIR/05-pause.txt"
docker ps -a --filter name=webserver \
  --format 'table {{.Names}}\t{{.Status}}' \
  | tee "$EVIDENCE_DIR/06-status-paused.txt"
set +e
curl --silent --show-error --max-time 3 http://localhost:80 \
  > "$EVIDENCE_DIR/07-access-while-paused.txt" 2>&1
paused_curl_exit="$?"
set -e
printf 'codigo_saida_curl=%s\n' "$paused_curl_exit" \
  | tee -a "$EVIDENCE_DIR/07-access-while-paused.txt"

docker unpause webserver | tee "$EVIDENCE_DIR/08-unpause.txt"
wait_for_http http://localhost:80
curl --silent --show-error --head http://localhost:80 \
  | tee "$EVIDENCE_DIR/09-nginx-unpaused.txt"

docker stop webserver | tee "$EVIDENCE_DIR/10-stop.txt"
docker ps -a --filter name=webserver \
  --format 'table {{.Names}}\t{{.Status}}' \
  | tee "$EVIDENCE_DIR/11-status-exited.txt"

event_end="$(date -u +%s)"
docker events --filter container=webserver --since "$event_start" --until "$event_end" \
  --format '{{.Time}}\t{{.Action}}\t{{.Actor.Attributes.name}}' \
  | tee "$EVIDENCE_DIR/12-events.txt"

section "Ação 2 - logs e execução interna"
docker start webserver | tee "$EVIDENCE_DIR/13-restart.txt"
wait_for_http http://localhost:80

set +e
timeout 8s docker logs -f webserver \
  > "$EVIDENCE_DIR/14-live-logs.txt" 2>&1 &
live_logs_pid="$!"
set -e
for _ in {1..7}; do
  curl --silent --fail http://localhost:80 >/dev/null
done
set +e
wait "$live_logs_pid"
live_logs_exit="$?"
set -e
printf '\ncodigo_saida_logs_f=%s (124 indica encerramento controlado pelo timeout)\n' \
  "$live_logs_exit" >> "$EVIDENCE_DIR/14-live-logs.txt"

docker logs --tail 5 webserver 2>&1 \
  | tee "$EVIDENCE_DIR/14-last-5-logs.txt"
docker exec webserver ls / \
  | tee "$EVIDENCE_DIR/15-exec-root-ls.txt"
docker exec webserver bash -lc 'cd /usr/share/nginx/html && pwd && ls -la' \
  | tee "$EVIDENCE_DIR/16-exec-nginx-html.txt"

section "Ação 3 - consumo de recursos"
docker run -d --name db -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PASSWORD" mysql:latest \
  | tee "$EVIDENCE_DIR/17-run-mysql.txt"
docker run -d --name cache redis:latest \
  | tee "$EVIDENCE_DIR/18-run-redis.txt"
docker run -d --name web nginx:latest \
  | tee "$EVIDENCE_DIR/19-run-nginx.txt"

wait_for_mysql
wait_for_http http://localhost:80

docker stats --no-stream \
  --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' \
  db cache web | tee "$EVIDENCE_DIR/20-stats-table.txt"

capture_stats "linha de base" 12 5 "$EVIDENCE_DIR/21-stats-baseline.tsv"
python3 scripts/analyze_stats.py \
  "$EVIDENCE_DIR/21-stats-baseline.tsv" \
  "$EVIDENCE_DIR/22-maximos-baseline.txt"
cat "$EVIDENCE_DIR/22-maximos-baseline.txt"

docker exec db mysql -uroot -p"$DB_ROOT_PASSWORD" -e \
  "CREATE DATABASE teste_carga; USE teste_carga; CREATE TABLE usuarios (id INT AUTO_INCREMENT PRIMARY KEY, nome VARCHAR(50)); INSERT INTO usuarios (nome) SELECT CONCAT('User', ROUND(RAND()*1000)) FROM INFORMATION_SCHEMA.COLUMNS LIMIT 1000;" \
  > "$EVIDENCE_DIR/23-mysql-load.txt" 2>&1 &
load_pid="$!"
capture_stats "durante a carga" 10 1 "$EVIDENCE_DIR/24-stats-during-load.tsv"
wait "$load_pid"
docker exec db mysql -uroot -p"$DB_ROOT_PASSWORD" -N -e \
  'SELECT COUNT(*) FROM teste_carga.usuarios;' \
  | awk '{print "registros_inseridos=" $1}' \
  | tee -a "$EVIDENCE_DIR/23-mysql-load.txt"
python3 scripts/analyze_stats.py \
  "$EVIDENCE_DIR/24-stats-during-load.tsv" \
  "$EVIDENCE_DIR/25-maximos-during-load.txt"
cat "$EVIDENCE_DIR/25-maximos-during-load.txt"

capture_stats "após a carga" 3 2 "$EVIDENCE_DIR/26-stats-after-load.tsv"
python3 scripts/analyze_stats.py \
  "$EVIDENCE_DIR/26-stats-after-load.tsv" \
  "$EVIDENCE_DIR/27-maximos-after-load.txt"
cat "$EVIDENCE_DIR/27-maximos-after-load.txt"

section "Ação 4 - remoção"
docker stop web | tee "$EVIDENCE_DIR/28-stop-web.txt"
docker rm web | tee "$EVIDENCE_DIR/29-rm-web.txt"

set +e
docker rm db > "$EVIDENCE_DIR/30-rm-running-db-error.txt" 2>&1
rm_running_exit="$?"
set -e
printf 'codigo_saida=%s\n' "$rm_running_exit" \
  | tee -a "$EVIDENCE_DIR/30-rm-running-db-error.txt"
cat "$EVIDENCE_DIR/30-rm-running-db-error.txt"

docker rm -f db | tee "$EVIDENCE_DIR/31-rm-force-db.txt"
docker run --rm -d --name temp nginx:latest \
  | tee "$EVIDENCE_DIR/32-run-auto-remove.txt"
docker stop temp | tee "$EVIDENCE_DIR/33-stop-auto-remove.txt"
if docker ps -a --format '{{.Names}}' | grep -Fxq temp; then
  echo 'temp_ainda_existe=sim'
else
  echo 'temp_ainda_existe=nao'
fi | tee "$EVIDENCE_DIR/34-confirm-auto-remove.txt"

docker stop webserver cache >/dev/null
docker container prune -f | tee "$EVIDENCE_DIR/35-container-prune.txt"
docker ps -a --format 'table {{.Names}}\t{{.Status}}' \
  | tee "$EVIDENCE_DIR/36-containers-final.txt"

printf '\nPrática concluída. Evidências em %s\n' "$EVIDENCE_DIR"
