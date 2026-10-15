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
echo "Creating service principal '${NAME}' (Contributor + User Access Administrator on ${SCOPE}, plus Graph permissions)..." >&2

# Contributor creates the resources; the lab template also creates an
# azurerm_role_assignment (Desktop Virtualization User) when avd_user_object_id is set,
# which requires User Access Administrator (or Owner).
# Reuse the service principal if it already exists (rerun-safe): just issue a new secret.
CLIENT_ID=$(az ad sp list --display-name "$NAME" --query '[0].appId' -o tsv)
if [[ -n "$CLIENT_ID" ]]; then
  echo "Service principal '${NAME}' already exists (${CLIENT_ID}); resetting its secret." >&2
  CLIENT_SECRET=$(az ad sp credential reset --id "$CLIENT_ID" --query password -o tsv)
else
  # tsv prints each list element on its own line, so read them one at a time.
  { read -r CLIENT_ID; read -r CLIENT_SECRET; } < <(
    az ad sp create-for-rbac --name "$NAME" --role Contributor --scopes "$SCOPE" \
      --query '[appId,password]' -o tsv
  )
fi
[[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]] || { echo "Failed to obtain client id/secret" >&2; exit 1; }

# Idempotent if the assignment already exists.
az role assignment create --assignee "$CLIENT_ID" --role Contributor --scope "$SCOPE" -o none
az role assignment create --assignee "$CLIENT_ID" \
  --role "User Access Administrator" --scope "$SCOPE" -o none

# Microsoft Graph application permissions so Terraform can create the Entra ID test
# users and group (User.ReadWrite.All, Group.ReadWrite.All, Directory.Read.All) and, for the
# domain-controller mode, configure Cloud Sync (Organization.ReadWrite.All,
# Application.ReadWrite.All, Synchronization.ReadWrite.All).
GRAPH=00000003-0000-0000-c000-000000000000
az ad app permission add --id "$CLIENT_ID" --api "$GRAPH" --api-permissions \
  741f803b-c850-494e-b5df-cde7c675a1ca=Role \
  62a82d76-70ea-41e2-9197-370581804d09=Role \
  7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role \
  292d869f-3427-49a8-9dab-8c70152b74e9=Role \
  1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9=Role \
  9b50c33d-700f-43b1-b2eb-87e89b703581=Role -o none
if ! az ad app permission admin-consent --id "$CLIENT_ID" 2>/dev/null; then
  echo "WARNING: admin consent failed. A Global Administrator or Privileged Role Administrator must run:" >&2
  echo "  az ad app permission admin-consent --id ${CLIENT_ID}" >&2
fi

cat <<OUT

Paste these into the Semaphore environment (AVD-Lab > Environment > extra variables / environment variables):

ARM_CLIENT_ID=${CLIENT_ID}
ARM_CLIENT_SECRET=${CLIENT_SECRET}
ARM_SUBSCRIPTION_ID=${SUB_ID}
ARM_TENANT_ID=${TENANT_ID}

The client secret is shown only once. Role assignments can take a minute to propagate.
OUT
