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
- `appliance_domain_name` — passed to the appliance's `domainname` step.
- `vm_size` — default `Standard_D4s_v3` (4 vCPU / 8 GB, the documented
  minimum, Gen 1 capable). The OS disk is 128 GiB.

## Connecting

Wait for first-run to finish (the Ansible step waits up to 20 minutes for
port 443), then browse to the `appliance_url` output. The certificate is
self-signed. SSH to `appliance_public_ip` as `root` (or `admin`) with the
appliance password.

## Caveats

- Not tested against a real deployment: `terraform validate` passes, but
  nothing has been applied in Azure. `terraform/templates/userdata.yml`
  mirrors Login VSI's `azure.yml` (password file, `first_run.chk`,
  `domainname`, `firstrun`); only the password and domain are templated.
- Login VSI's sample `azure.yml` uses the VM's Azure DNS name (e.g.
  `westeurope.cloudapp.azure.com`) as the domain name. The default
  `appliance_domain_name` here is a placeholder; set it to whatever name you
  want the appliance to use.
- The public IP and NSG are for a short-lived lab. For private-only
  access (ExpressRoute/VPN, as the docs describe) remove the public IP from
  `main.tf`.
