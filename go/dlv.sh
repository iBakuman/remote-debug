#!/usr/bin/env bash
set -x

FILE_CHANGE_LOG_FILE=/tmp/changes.log
APP_ARGS="$@"

if [ -z "$SRC_DIR" ]; then
  echo "Error: SRC_DIR environment variable is not set."
  exit 1
fi

# Remove trailing slash from SRC_DIR if it exists
SRC_DIR=${SRC_DIR%/}

if [ -z "$MAIN_FILE_PATH" ]; then
  echo "Error: MAIN_FILE_PATH environment variable is not set."
  exit 1
fi

if [[ "$MAIN_FILE_PATH" == /* ]]; then
  echo "Error: MAIN_FILE_PATH must be a relative path, cannot start with '/'"
  exit 1
fi

cd "$SRC_DIR" || { echo "Failed to cd ${SRC_DIR}"; exit 1; }

echo "SRC_DIR environment is set to: $SRC_DIR"

log() {
  echo "***** $1 *****"
}

init() {
  log "Initializing"
  truncate -s 0 ${FILE_CHANGE_LOG_FILE}
  tail -f ${FILE_CHANGE_LOG_FILE} &
}

build() {
  log "Building executable binary"
  go env -w GOPROXY="proxy.golang.org,direct"
  go mod download
  if ! go build -buildvcs=false -gcflags "all=-N -l" -o /app "./${MAIN_FILE_PATH}";then
    echo -e "\033[31m[ERROR]Build failed"
    return 1
  fi
}

start() {
  log "Starting Delve"
  (
    kill_dlv() {
      log "Kill dlv_pid: $dlv_pid"
      kill -9 "$dlv_pid"
      exit 0
    }
    trap kill_dlv SIGTERM
    while true; do
      dlv --listen=:"${DELVE_PORT}" --headless=true --api-version=2 --accept-multiclient exec /app -- ${APP_ARGS} &
      dlv_pid=$!
      echo -e "\033[34m[INFO]Debugger started successfully, its pid is $dlv_pid"
      wait
    done
  )&
  loop_pid=$!
  echo -e "\033[32m[INFO]Get loop_pid: $loop_pid"
}

restart() {
  if ! build;then
    return 1
  fi

  log "Killing old processes"
  kill "$loop_pid"
  killall"app"

  start
}

watch() {
  echo -e "\033[32m[INFO]Watching for changes"
  inotifywait -e "MODIFY,DELETE,MOVED_TO,MOVED_FROM" -m -r ${PWD} | (
    while true; do
      read path action file
      ext=${file: -3}
      if [[ "$ext" == ".go" ]]; then
        echo "$file"
      fi
    done
  ) | (
    WAITING=""
    while true; do
      file=""
      read -t 1 file
      if test -z "$file"; then
        if test ! -z "$WAITING"; then
          echo "CHANGED"
          WAITING=""
        fi
      else
        log "File ${file} changed" >> ${FILE_CHANGE_LOG_FILE}
        WAITING=1
      fi
    done
  ) | (
    while true; do
      read TMP
      restart
    done
  )
}

init
if build;then start; fi
watch
