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

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

init() {
  touch "$FILE_CHANGE_LOG_FILE"
  cd "$SRC_DIR" || exit 1
}

build() {
  log "Building..."
  if ! go build -gcflags="all=-N -l" -o /tmp/debug "$MAIN_FILE_PATH"; then
    log "Build failed"
    return 1
  fi
  log "Build successful"
  return 0
}

start() {
  log "Starting debugger..."
  if [ -f /tmp/debug.pid ]; then
    if kill -0 "$(cat /tmp/debug.pid)" 2>/dev/null; then
      log "Debugger is already running"
      return 1
    fi
    rm /tmp/debug.pid
  fi
  
  dlv --listen=:${DELVE_PORT} --headless=true --api-version=2 --accept-multiclient exec /tmp/debug $APP_ARGS &
  echo $! > /tmp/debug.pid
  log "Debugger started"
}

restart() {
  if [ -f /tmp/debug.pid ]; then
    log "Stopping debugger..."
    kill "$(cat /tmp/debug.pid)" 2>/dev/null
    rm /tmp/debug.pid
  fi
  if build; then
    start
  fi
}

watch() {
  log "Watching for file changes..."
  inotifywait -m -r -e modify -e create -e delete -e move "$SRC_DIR" --format '%w%f' --exclude '\.git/.*' | while read -r file; do
    if [[ "$file" =~ \.go$ ]]; then
      echo "$(date +%s)" > "$FILE_CHANGE_LOG_FILE"
      # Wait for 100ms to aggregate changes
      sleep 0.1
      # Check if there are more recent changes
      if [ "$(cat "$FILE_CHANGE_LOG_FILE")" = "$(date +%s)" ]; then
        log "Detected change in: $file"
        restart
      fi
    fi
  done
}

init
if build; then start; fi
watch
