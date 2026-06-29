#!/bin/bash
set -euo pipefail

ADC_MOUNT="/mnt/gcloud-adc/application_default_credentials.json"
ADC_TARGET="/home/sandbox/.config/gcloud/application_default_credentials.json"

if [ -f "${ADC_MOUNT}" ]; then
    cp "${ADC_MOUNT}" "${ADC_TARGET}"
    chown sandbox:sandbox "${ADC_TARGET}"
    chmod 600 "${ADC_TARGET}"
    export GOOGLE_APPLICATION_CREDENTIALS="${ADC_TARGET}"
fi

exec /opt/vandbox/scripts/entrypoint.sh "$@"
