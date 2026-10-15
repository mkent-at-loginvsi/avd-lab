#!/usr/bin/env bash
# Turns the Login VSI appliance .zip into a ready-to-copy .vhd page blob in Azure.
#
# Login VSI ships the Azure appliance as a ~6.5 GB zip containing a fixed VHD.
# Azure's server-side copy (what the terraform template uses) can't unzip, so
# this script runs a short-lived Linux VM inside Azure that downloads the zip,
# extracts it, and uploads the VHD as a page blob. The VM and its disk/NIC are
# deleted afterwards. Prints a read-only SAS URL to use as `vhd_source_url`.
#
# Usage: stage-vhd.sh <resource-group> <location> <zip-url> [storage-account]
#   resource-group   must already exist
#   storage-account  reused if it exists, otherwise created (default: stlevhdstg<random>)
#
# Requires: az CLI logged in to the target subscription, openssl.
set -euo pipefail

RG=${1:?usage: $0 <resource-group> <location> <zip-url> [storage-account]}
LOC=${2:?missing location}
ZIP_URL=${3:?missing zip url}
SA=${4:-stlevhdstg$(openssl rand -hex 3)}
VM=vm-vhdstage-$(openssl rand -hex 2)
VM_SIZE=${VM_SIZE:-Standard_D4s_v4}
CONTAINER=vhds
BLOB=LoginEnterprise.vhd

WORK=$(mktemp -d)
VM_CREATED=0

cleanup() {
  rm -rf "$WORK"
  if [ "$VM_CREATED" = 1 ]; then
    echo "Deleting staging VM $VM (and its OS disk and NIC)..." >&2
    az vm delete -g "$RG" -n "$VM" --yes -o none || echo "WARNING: delete $VM manually" >&2
  fi
}
trap cleanup EXIT

az group show -n "$RG" -o none

if ! az storage account show -g "$RG" -n "$SA" -o none 2>/dev/null; then
  echo "Creating storage account $SA..." >&2
  az storage account create -g "$RG" -n "$SA" -l "$LOC" --sku Standard_LRS \
    --allow-blob-public-access false -o none
fi
KEY=$(az storage account keys list -g "$RG" -n "$SA" --query '[0].value' -o tsv)
az storage container create --account-name "$SA" --account-key "$KEY" -n "$CONTAINER" -o none

# Marker blobs left from a previous run would make us return early.
for m in done.txt fail.txt; do
  az storage blob delete --account-name "$SA" --account-key "$KEY" -c "$CONTAINER" -n "$m" -o none 2>/dev/null || true
done

# Write SAS for the VM (expires in 1 day) and a read-only SAS for the final URL.
expiry() { date -u -d "+$1 days" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -v+"$1"d +%Y-%m-%dT%H:%MZ; }
WSAS=$(az storage container generate-sas --account-name "$SA" --account-key "$KEY" -n "$CONTAINER" \
  --permissions racwl --expiry "$(expiry 1)" --https-only -o tsv)
BASE="https://$SA.blob.core.windows.net/$CONTAINER"

cat > "$WORK/stage.sh" <<SCRIPT
#!/bin/bash
exec > /var/log/stage.log 2>&1
BASE="$BASE"
SAS="$WSAS"
fail() { echo failed > /tmp/fail.txt; /work/azcopy copy /tmp/fail.txt "\$BASE/fail.txt?\$SAS"; }
trap fail ERR
set -ex
apt-get update && apt-get install -y unzip curl
mkdir -p /work && cd /work
curl -fL https://aka.ms/downloadazcopy-v10-linux | tar xz --strip-components=1
curl -fL -o va.zip "$ZIP_URL"
unzip -o va.zip && rm va.zip
VHD=\$(find /work -iname '*.vhd' | head -1)
test -n "\$VHD"
./azcopy copy "\$VHD" "\$BASE/$BLOB?\$SAS" --blob-type PageBlob
echo done > /tmp/done.txt
./azcopy copy /tmp/done.txt "\$BASE/done.txt?\$SAS"
SCRIPT

# The VM only needs outbound internet: no public IP, no NSG, random throwaway password.
PW="$(openssl rand -base64 18 | tr -d '/+=')Aa1"
echo "Creating staging VM $VM ($VM_SIZE) in $LOC..." >&2
az vm create -g "$RG" -n "$VM" -l "$LOC" --size "$VM_SIZE" --image Ubuntu2204 \
  --os-disk-size-gb 300 --storage-sku StandardSSD_LRS \
  --os-disk-delete-option Delete --nic-delete-option Delete \
  --authentication-type password --admin-username stageadmin --admin-password "$PW" \
  --public-ip-address "" --nsg "" --custom-data "$WORK/stage.sh" -o none
VM_CREATED=1

echo "Waiting for the VM to download, extract and upload the VHD (usually 15-30 min)..." >&2
for _ in $(seq 1 240); do
  for m in done fail; do
    exists=$(az storage blob exists --account-name "$SA" --account-key "$KEY" -c "$CONTAINER" -n "$m.txt" --query exists -o tsv)
    if [ "$exists" = true ]; then
      if [ "$m" = fail ]; then
        echo "Staging failed. Log from the VM:" >&2
        az vm run-command invoke -g "$RG" -n "$VM" --command-id RunShellScript \
          --scripts 'tail -40 /var/log/stage.log' --query 'value[0].message' -o tsv >&2 || true
        exit 1
      fi
      RSAS=$(az storage container generate-sas --account-name "$SA" --account-key "$KEY" -n "$CONTAINER" \
        --permissions rl --expiry "$(expiry 7)" --https-only -o tsv)
      echo "Staged $BLOB in storage account $SA. Use this as vhd_source_url (valid 7 days):" >&2
      echo "$BASE/$BLOB?$RSAS"
      exit 0
    fi
  done
  sleep 30
done
echo "Timed out waiting for the VHD upload" >&2
exit 1
