# azure-loginenterprise-appliance

Deploys a single Login Enterprise virtual appliance to Azure with Terraform,
following Login VSI's
[Azure deployment guide](https://docs.loginvsi.com/login-enterprise/6.9/deploying-the-vhd-to-microsoft-azure)
and the cloud-init approach from
[Appliance-Terraform-vSphere-Example](https://github.com/LoginVSI/Appliance-Terraform-vSphere-Example).

Terraform creates a resource group, VNet/subnet, NSG, public IP, a storage
account, and then:

1. **Uploads the VHD** — Azure copies it server-side from `vhd_source_url`
   into a page blob in the lab's storage account (nothing passes through the
   machine running Terraform).
2. **Creates a managed image** from that blob (Linux, Hyper-V
   **Generation 1**, as the docs require).
3. **Builds the cloud-init** (`azure.yml` equivalent) from your variables:
   Base64 admin password, domain name, `/loginvsi/bin/firstrun`.
4. **Creates the VM** from the image with that cloud-init as `custom_data`.

This replaces the manual Storage Explorer, `az image create`, `azure.yml`
editing and `az vm create` steps from the docs.

## Getting a `vhd_source_url`

Login VSI distributes the Azure appliance as a zip (about 6.5 GB, containing a
fixed VHD of tens of GB). Azure's server-side copy can't unzip, so
`scripts/stage-vhd.sh` converts it once:

```
scripts/stage-vhd.sh <resource-group> <location> <zip-url> [storage-account]
```

It creates a storage account (or reuses the one you name), runs a throwaway
Linux VM in Azure that downloads and extracts the zip and uploads the VHD as a
page blob, deletes the VM, and prints a 7-day read-only SAS URL on stdout.
Pass that as `vhd_source_url`. The resource group must already exist, and the
VM needs no public IP or inbound access. Expect roughly 15-30 minutes. Delete
the staging storage account when you no longer need it (the lab makes its own
copy).

If you already have a direct `.vhd` or SAS URL, skip the script.

The URL must stay reachable while Azure copies it, and is treated as a secret
since it embeds a token. The VHD is large, so the first `terraform apply` is
slow while the lab's own copy runs (the provider waits for it; the blob
resource's create timeout is not configurable). Each lab instance makes its
own copy, and destroying the lab deletes it.

## Deploying into an existing resource group

Set `resource_group_name` and `create_resource_group=false` (a Terraform
variable only; Lab Manager always creates the group). Terraform then adds its
resources to that group and `terraform destroy` removes only what it created,
never the group.

## State

When run by hand, Terraform keeps state in `terraform/terraform.tfstate`. It
contains the passwords and SAS URL in plain text, so it is gitignored; don't
commit or share it.

## Variables

- `vhd_source_url` — where Azure should copy the appliance `.vhd` from (required).
- `appliance_admin_password` — appliance admin/root password; Base64-encoded
  into cloud-init for you (required).
- `vm_admin_password` — password for the Azure VM account
  (`vm_admin_username`, default `azureadministrator`); Azure complexity rules
  apply (required).
- `admin_source_cidr` — your public IP/32; only this CIDR can reach 443 and
  22 (required).
- `dns_hostname` — the VM's hostname and its public DNS name,
  `<dns_hostname>.<location>.cloudapp.azure.com` (lowercase letters, digits,
  hyphens; must be unique in the region). Default `leappliance`; empty generates `le-<suffix>`. Shown in the
  `appliance_fqdn` output.
- `deploy_launcher` — also create a Windows 11 launcher VM (`vm-launcher`, default size
  `launcher_vm_size` = `Standard_D2as_v4`) in the appliance's subnet. RDP to its
  `launcher_public_ip` from `admin_source_cidr` as `vm_admin_username` / `vm_admin_password`;
  it reaches the appliance at the appliance's private address. Needs Windows client
  licensing (the VM sets `license_type = Windows_Client`). Turning it off on a later run
  destroys the launcher.
- `appliance_domain_name` — passed to the appliance's `domainname` step. Empty
  (the default) uses the regional zone, `<location>.cloudapp.azure.com`, as Login VSI's
  sample `azure.yml` does, so the appliance's own address is `<dns_hostname>.<zone>`.
  Changing it changes cloud-init, which makes Terraform replace the VM.
- `vm_size` — default `Standard_D4s_v3` (4 vCPU / 8 GB, the documented
  minimum, Gen 1 capable). The OS disk is 128 GiB.

## Connecting

Wait for first-run to finish (the Ansible step waits up to 20 minutes for
port 443), then browse to the `appliance_url` output (the public DNS name). The certificate is
self-signed. SSH to `appliance_fqdn` (or `appliance_public_ip`) as `admin` with the
appliance password (`root` is not set by the cloud-init).

## Caveats

- Not tested against a real deployment: `terraform validate` passes, but
  nothing has been applied in Azure. `terraform/templates/userdata.yml`
  mirrors Login VSI's `azure.yml` (password file, `first_run.chk`,
  `domainname`, `firstrun`); only the password and domain are templated.
- Login VSI's sample `azure.yml` uses the VM's Azure DNS name (e.g.
  `westeurope.cloudapp.azure.com`) as the domain name. This template does the same by
  default: it uses `dns_hostname` as both the VM hostname and the public IP's DNS label, and
  passes the regional zone as the appliance's domain name. Set `appliance_domain_name` only if you want a different one.
- The public IP and NSG are for a short-lived lab. For private-only
  access (ExpressRoute/VPN, as the docs describe) remove the public IP from
  `main.tf`.
