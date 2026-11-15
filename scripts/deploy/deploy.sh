#!/usr/bin/env bash
# Personal project, not for production, as is; not affiliated with the author's employer, Liquidware, ServiceNow or Microsoft.
set -euo pipefail

PARAM_FILE="parameters/lab.bicepparam"
CLOUD="${AVD_CLOUD:-commercial}"
LOCATION="${AVD_LOCATION:-eastus2}"
RESOURCE_GROUP="rg-avd-hub-dev"
OUTPUT_FILE="networking-outputs.json"
WHAT_IF=false

usage() {
  cat <<EOF
Usage: $0 [-p <param-file>] [--cloud commercial|usgov] [-l <location>] [-g <resource-group>] [-o <output-file>] [--what-if]
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--param-file) PARAM_FILE="$2"; shift 2 ;;
    --cloud) CLOUD="$2"; shift 2 ;;
    -l|--location) LOCATION="$2"; shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -o|--output-file) OUTPUT_FILE="$2"; shift 2 ;;
    --what-if) WHAT_IF=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

CLOUD="${CLOUD,,}"
[[ "$CLOUD" == commercial || "$CLOUD" == usgov ]] || { echo "--cloud takes commercial or usgov: '$CLOUD'" >&2; exit 1; }
USGOV_REGIONS=" usgovvirginia usgovarizona usgovtexas "
if [[ "$CLOUD" == usgov && "$USGOV_REGIONS" != *" ${LOCATION,,} "* ]]; then
  echo "Azure US Government deployments require a US Gov region (usgovvirginia, usgovarizona, usgovtexas); got '$LOCATION'." >&2
  exit 1
fi
ACTIVE_AZ_CLOUD=$(az cloud show --query name -o tsv 2>/dev/null || true)
EXPECTED_AZ_CLOUD=$([[ "$CLOUD" == usgov ]] && echo "AzureUSGovernment" || echo "AzureCloud")
if [[ -n "$ACTIVE_AZ_CLOUD" && "$ACTIVE_AZ_CLOUD" != "$EXPECTED_AZ_CLOUD" ]]; then
  echo "Active az cloud is '$ACTIVE_AZ_CLOUD', expected '$EXPECTED_AZ_CLOUD' for --cloud $CLOUD." >&2
  exit 1
fi
export AVD_CLOUD="$CLOUD"
export AVD_LOCATION="$LOCATION"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

if [[ "$WHAT_IF" == "true" ]]; then
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file bicep/main.bicep \
    --parameters "$PARAM_FILE"
  exit 0
fi

DEPLOY_NAME="avd-networking-$(date -u +%Y%m%d%H%M%S)"
az deployment group create \
  --name "$DEPLOY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file bicep/main.bicep \
  --parameters "$PARAM_FILE" \
  --query "properties.outputs.networkingOutputs.value" \
  --output json > "$OUTPUT_FILE"

echo "Wrote C31 outputs to $OUTPUT_FILE"
