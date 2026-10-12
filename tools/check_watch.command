#!/bin/bash
# Leave this running in Terminal. When Logs/check_request appears, it runs tools/check.command.
# Lets a remote Claude session request a build by creating that file.
cd "$(dirname "$0")/.." || exit 1
mkdir -p Logs
echo "Watching for Logs/check_request in $(pwd) (Ctrl-C to stop)"
while true; do
  if [ -f Logs/check_request ]; then
    rm -f Logs/check_request
    echo "Check requested at $(date)"
    "$(dirname "$0")/check.command" > /dev/null 2>&1
    echo "Check finished at $(date)"
  fi
  sleep 3
done
