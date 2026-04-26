#!/bin/bash

# Protection Alpine
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"recommended_download":"[^"]*"' | cut -d'"' -f4)
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
fi

echo "[YorkHost] Lancement de FXServer..."
