# avd-lab (Semaphore)

Semaphore port of the Lab Manager `azure-avd-lab` template, reworked so the test
users can sign in to AVD (web client / Windows App):

- Session hosts (Windows 11 multi-session) are **Entra-joined** (`AADLoginForWindows`);
  the host pool sets `targetisaadjoined:i:1`.
- Terraform creates cloud-only Entra users `testuser01..N@<tenant>.onmicrosoft.com`
  (shared `test_user_password`) in a `SessionDesktop-*` group that has
  **Desktop Virtualization User** on the app group and **Virtual Machine User Login**
  on the resource group.
- `deploy_domain_controller=true` switches to AD mode: a DC, domain-joined session hosts and
  AD test users synced to Entra with Cloud Sync (password hash sync), so sign-in is Entra
  first, then the Windows Security prompt with the AD credentials. Default off. The Graph calls run
  as the service principal; registering the Cloud Sync agent on the DC needs a user, so create a
  cloud account with only the Hybrid Identity Administrator role (e.g. `cloudsync-agent@<tenant>`)
  and enter it at the `entra_admin_*` prompts. Global admins are blocked by security-defaults MFA.

Files:
- `ansible/deploy.yml` - Semaphore entrypoint: `terraform apply`, build inventory from
  the `ansible_inventory` output, then run `site.yml` (optional DC + AVD agent registration).
- `ansible/destroy.yml` - `terraform destroy`.
- `scripts/create-service-principal.sh` - creates the service principal (Azure roles plus
  Graph `User.ReadWrite.All`, `Group.ReadWrite.All`, `Directory.Read.All`, admin-consented)
  and prints the `ARM_*` values for the Semaphore environment.

Requirements: every test user needs an AVD-eligible license (Microsoft 365 E3/E5/Business
Premium or per-user AVD access), and must be exempt from MFA/Conditional Access rules that
block automated sign-in. `test_user_password` must meet Entra password complexity.

Terraform state is stored at `/var/lib/semaphore/tfstate/avd-lab.tfstate` on the
Semaphore host (a persistent volume).

## Login Enterprise appliance (`appliance/`)

Port of the Lab Manager `azure-loginenterprise-appliance` template: one Login Enterprise
Linux appliance (Hyper-V Gen 1 VHD) - the VHD is copied server-side into a new storage
account, turned into a managed image, and the VM is configured by cloud-init.

- `appliance/terraform/` - the Terraform (own state, separate from the AVD lab).
- `appliance/ansible/deploy.yml` / `destroy.yml` - Semaphore entrypoints; destroy needs no prompts.
- `scripts/stage-vhd.sh` - one-time conversion of Login VSI's appliance zip into a VHD page
  blob and a 7-day SAS URL to use as `vhd_source_url`.
- State: `/var/lib/semaphore/tfstate/le-appliance.tfstate`.

Deploy prompts: `vhd_source_url` (secret), `appliance_admin_password` (secret),
`vm_admin_password` (secret), `admin_source_cidr`, optional `vm_size` (default
`Standard_D4s_v4`, 4 vCPU), `dns_hostname` (public name
`<hostname>.<region>.cloudapp.azure.com`) and `appliance_domain_name` (defaults to that name). Uses the same `azure-avd-lab`
Semaphore environment (Azure service principal). Each lab makes its own VHD copy, so the
first apply is slow and destroy removes it. See `appliance/README.labmgr.md` for details.

See `README.labmgr.md` for the original Lab Manager description.

## Publishing a RemoteApp

Deploy takes `remoteapp_name`, `remoteapp_path` and `remoteapp_arguments` (a fixed command line
passed on every launch, e.g. the appliance URL; users can't change it), plus an optional icon
(`remoteapp_icon_path` / `remoteapp_icon_index`: a file on the session host and an index in it;
empty path = the program's own icon). When the path is set, Terraform adds a
RemoteApp application group (`rag-avdlab-*`) on the host pool, publishes that program, registers
the group with the workspace and grants the `SessionDesktop-*` group (the same users as the
desktop) the Desktop Virtualization User role on it. The program must already be installed at
that path on every session host. Leave the path empty to publish no RemoteApp.

