#!/usr/bin/env bash

FILE_CHANGE_LOG_FILE=/tmp/changes.log
SERVICE_ARGS="$@"

if [ -z "$SRC_DIR" ]; then
  echo "Error: SRC_DIR environment variable is not set."
  exit 1
else
  cd "$SRC_DIR" || { echo "Failed to cd ${SRC_DIR}"; exit 1; }
  SERVICE_NAME=$(basename "$SRC_DIR")
  echo "SERVICE_NAME: ${SERVICE_NAME}"
fi

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
  log "Building ${SERVICE_NAME} binary"
  go env -w GOPROXY="proxy.golang.org,direct"
  go mod download
  if ! go build -buildvcs=false -gcflags "all=-N -l" -o /${SERVICE_NAME};then
    echo -e "\033[31m[ERROR]Build failed"
    return 1
  fi
  chmod +x /${SERVICE_NAME}
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
      dlv --listen=:"${DELVE_PORT}" --headless=true --api-version=2 --accept-multiclient exec /"${SERVICE_NAME}" -- ${SERVICE_ARGS} &
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
  killall "${SERVICE_NAME}"

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
