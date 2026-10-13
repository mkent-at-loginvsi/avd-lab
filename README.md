# avd-lab (Semaphore)

Semaphore port of the Lab Manager `azure-avd-lab` template. See `README.labmgr.md`
for what the lab builds.

- `ansible/deploy.yml` — Semaphore entrypoint: `terraform apply`, build inventory from
  the `ansible_inventory` output, then run `site.yml`.
- `ansible/destroy.yml` — `terraform destroy`.
- `scripts/create-service-principal.sh` — creates the Azure service principal and
  prints the `ARM_*` values for the Semaphore environment.

Terraform state is stored at `/var/lib/semaphore/tfstate/avd-lab.tfstate` on the
Semaphore host — mount a volume there or the state is lost with the container.
