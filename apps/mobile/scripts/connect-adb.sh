#!/usr/bin/env bash
set -euo pipefail

HOST="${ADB_CONNECT_HOST:-host.docker.internal}"
PORT="${ADB_CONNECT_PORT:-5555}"

echo "[connect-adb] Trying adb connect ${HOST}:${PORT}"
adb connect "${HOST}:${PORT}" || true

echo "[connect-adb] adb devices:"
adb devices || true

# うまくいかない時の救済処置として、WSLのnameserver IP を試す
if ! adb devices | grep -q "${PORT}"; then
  NS_IP="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf || true)"
  if [ -n "${NS_IP}" ]; then
    echo "[connect-adb] Fallback: adb connect ${NS_IP}:${PORT}"
    adb connect "${NS_IP}:${PORT}" || true
    adb devices || true
  fi
fi