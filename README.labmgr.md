# azure-avd-lab

Stands up a small Azure Virtual Desktop lab:

- A Windows Server 2022 VM promoted to the first domain controller of a new
  Active Directory forest (`domain_name`).
- A pooled AVD host pool (breadth-first load balancing) with
  `session_host_count` Windows 11 multi-session VMs, domain-joined to that
  forest.
- A "Desktop" application group, a workspace, and (if `avd_user_object_id`
  is set) a role assignment granting that Entra ID user or group the
  **Desktop Virtualization User** role so they can launch the published
  full desktop.
- `test_user_count` AD test accounts (`testuser01`, `testuser02`, ...),
  members of a `SessionDesktop` AD group that's granted local RDP access
  (`Remote Desktop Users`) on every session host — useful for load testing
  directly against the session hosts. These are plain on-prem AD accounts;
  since this forest isn't synced to Entra ID, they can't be granted the
  Desktop Virtualization User role or appear in the AVD feed/broker.

## How it works

Terraform provisions the network, VMs, and AVD control-plane objects, then
outputs `ansible_inventory`. Lab Manager runs `ansible/site.yml` against
that inventory to:

1. Promote the DC (`microsoft.ad.domain`, forest creation + reboot).
2. Create the `SessionDesktop` AD group and `test_user_count` test
   accounts, added to that group (`microsoft.ad.group`, `microsoft.ad.user`).
3. Join each session host to the domain (`microsoft.ad.membership`) and
   add `SessionDesktop` to its local `Remote Desktop Users` group
   (`win_group_membership`).
4. Install the AVD Boot Loader and Agent MSIs on each session host and
   register them with the host pool using the token Terraform generated.

Every VM gets a `CustomScriptExtension` at boot that enables WinRM (HTTP,
basic auth) so Ansible can connect immediately — access is restricted by
the NSG to `admin_source_cidr` only. This is intentionally simple for a
short-lived lab; it is **not** a hardened configuration and shouldn't be
reused for anything long-lived or exposed beyond your own IP.

## Prerequisites on the Lab Manager host

- Azure credentials available to the `azurerm` Terraform provider (e.g.
  `az login`, or `ARM_CLIENT_ID`/`ARM_CLIENT_SECRET`/`ARM_SUBSCRIPTION_ID`/
  `ARM_TENANT_ID` environment variables) with rights to create resource
  groups, networking, VMs, and AVD objects in the target subscription.
- An Entra ID / Azure subscription with AVD entitlement for the number of
  session hosts and users you plan to use (Windows 11 Enterprise
  multi-session + AVD access rights, e.g. via Microsoft 365 or a
  per-user AVD license). This template does not manage licensing.
- Ansible collections installed once: `ansible-galaxy collection install -r ansible/requirements.yml`.

## Required variables

- `admin_source_cidr` has no default — set it to your own public IP (e.g.
  `203.0.113.4/32`) so RDP and WinRM aren't reachable from the whole
  internet.
- `test_user_password` has no default — set a password for the AD test
  accounts (shared across all of them).
