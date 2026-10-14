# avd-lab (Semaphore)

Semaphore port of the Lab Manager `azure-avd-lab` template, reworked so the test
users can sign in to AVD (web client / Windows App):

- Session hosts (Windows 11 multi-session) are **Entra-joined** (`AADLoginForWindows`);
  the host pool sets `targetisaadjoined:i:1`.
- Terraform creates cloud-only Entra users `testuser01..N@<tenant>.onmicrosoft.com`
  (shared `test_user_password`) in a `SessionDesktop-*` group that has
  **Desktop Virtualization User** on the app group and **Virtual Machine User Login**
  on the resource group.
- `deploy_domain_controller=true` additionally deploys a standalone AD forest (not
  joined to the session hosts); default off.

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

See `README.labmgr.md` for the original Lab Manager description.
