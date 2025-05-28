#!/usr/bin/env bash

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

# Function to kill processes using the delve port
kill_port_processes() {
  if [ -n "$DELVE_PORT" ]; then
    log "Checking for processes using port $DELVE_PORT"
    local pids=$(lsof -ti:$DELVE_PORT 2>/dev/null)
    if [ -n "$pids" ]; then
      log "Killing processes using port $DELVE_PORT: $pids"
      echo "$pids" | xargs kill -9 2>/dev/null || true
      sleep 1
      # Double check if port is still in use
      local remaining_pids=$(lsof -ti:$DELVE_PORT 2>/dev/null)
      if [ -n "$remaining_pids" ]; then
        log "Force killing remaining processes: $remaining_pids"
        echo "$remaining_pids" | xargs kill -9 2>/dev/null || true
        sleep 2
      fi
    fi
  fi
}

# Function to wait for port to be available
wait_for_port_available() {
  if [ -n "$DELVE_PORT" ]; then
    local max_attempts=10
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
      if ! lsof -ti:$DELVE_PORT >/dev/null 2>&1; then
        log "Port $DELVE_PORT is now available"
        return 0
      fi
      log "Waiting for port $DELVE_PORT to be released... (attempt $((attempt+1))/$max_attempts)"
      sleep 1
      attempt=$((attempt+1))
    done
    log "Warning: Port $DELVE_PORT may still be in use after $max_attempts attempts"
  fi
}

init() {
  log "Initializing"
  truncate -s 0 ${FILE_CHANGE_LOG_FILE}
  tail -f ${FILE_CHANGE_LOG_FILE} &
}

build() {
  log "Building executable binary"
  go env -w GOPROXY="proxy.golang.org,direct"
  go mod tidy
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
      kill -9 "$dlv_pid" 2>/dev/null || true
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
  log "Killing old processes"
  
  # Kill the loop process
  if [ -n "$loop_pid" ]; then
    kill "$loop_pid" 2>/dev/null || true
  fi
  
  # Kill all dlv processes
  pkill -f "dlv.*--listen=:${DELVE_PORT}" 2>/dev/null || true
  
  # Kill all app processes
  killall "app" 2>/dev/null || true
  
  # Kill any processes using the delve port
  kill_port_processes
  
  # Wait for port to be available
  wait_for_port_available

  if ! build;then
    return 1
  fi

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
