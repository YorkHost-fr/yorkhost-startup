#!/bin/bash
if [ ! -x "$(pwd)/alpine/opt/cfx-server/FXServer" ]; then
  echo "** Alpine missing or broken, reinstalling artifacts..."
  rm -rf alpine
  DOWNLOAD_LINK=$(curl -sSL https://changelogs-live.fivem.net/api/changelog/versions/linux/server | grep -o '"latest_download":"[^"]*"' | cut -d'"' -f4)
  echo "Downloading: ${DOWNLOAD_LINK}"
  curl -sSL "${DOWNLOAD_LINK}" -o fx.tar.xz
  tar xf fx.tar.xz
  rm -f fx.tar.xz
  echo "** Artifacts reinstalled."
fi
