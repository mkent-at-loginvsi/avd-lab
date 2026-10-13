#!/usr/bin/env bash
# Creates an Azure service principal for Semaphore to run the AVD lab Terraform.
# Prints the four ARM_* values to paste into the Semaphore environment.
#
# Usage: ./create-service-principal.sh [subscription-id-or-name] [sp-name]
#   Requires: az CLI, logged in (az login) with rights to create app registrations
#   and to assign roles on the subscription.
set -euo pipefail

SUB="${1:-$(az account show --query id -o tsv)}"
NAME="${2:-semaphore-avd-lab}"

az account set --subscription "$SUB"
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SCOPE="/subscriptions/${SUB_ID}"

echo "Subscription: ${SUB_ID}"
echo "Creating service principal '${NAME}' (Contributor + User Access Administrator on ${SCOPE})..." >&2

# Contributor creates the resources; the lab template also creates an
# azurerm_role_assignment (Desktop Virtualization User) when avd_user_object_id is set,
# which requires User Access Administrator (or Owner).
read -r CLIENT_ID CLIENT_SECRET < <(
  az ad sp create-for-rbac --name "$NAME" --role Contributor --scopes "$SCOPE" \
    --query '[appId,password]' -o tsv
)
az role assignment create --assignee "$CLIENT_ID" \
  --role "User Access Administrator" --scope "$SCOPE" -o none

cat <<OUT

Paste these into the Semaphore environment (AVD-Lab > Environment > extra variables / environment variables):

ARM_CLIENT_ID=${CLIENT_ID}
ARM_CLIENT_SECRET=${CLIENT_SECRET}
ARM_SUBSCRIPTION_ID=${SUB_ID}
ARM_TENANT_ID=${TENANT_ID}

The client secret is shown only once. Role assignments can take a minute to propagate.
OUT
