#!/bin/bash
set -e

ADC_MOUNT="/mnt/gcloud-adc/application_default_credentials.json"
ADC_TARGET="/home/opencode/.config/gcloud/application_default_credentials.json"

if [ "$(id -un)" != "opencode" ]; then
    if [ -f "${ADC_MOUNT}" ]; then
        mkdir -p /home/opencode/.config/gcloud
        if cp "${ADC_MOUNT}" "${ADC_TARGET}" 2>/dev/null; then
            chown opencode:opencode "${ADC_TARGET}"
            chmod 600 "${ADC_TARGET}"
        else
            echo "Warning: could not copy GCP credentials (permission denied)" >&2
        fi
    fi
    exec runuser -u opencode -- "$@"
fi

exec "$@"
