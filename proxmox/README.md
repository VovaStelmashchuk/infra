# Proxmox VE Installation Playbook

Installs Proxmox VE 8.x on a bare Debian 12 (Bookworm) server using Ansible.

## Prerequisites

- A fresh **Debian 12 (Bookworm)** server with root SSH access
- The `ROOT_SSH_PRIVATE_KEY` secret configured in GitHub Actions
- Ansible installed on your control machine (for local runs)

## How it works

The playbook performs these steps in order:

1. Verifies the OS is Debian 12
2. Sets the server hostname to the provided FQDN
3. Configures `/etc/hosts` with the correct IP-to-FQDN mapping
4. Adds the Proxmox GPG key and no-subscription APT repository
5. Runs a full system upgrade
6. Installs `proxmox-ve`, `postfix`, `open-iscsi`, and `chrony`
7. Removes the default Debian kernel (so only the Proxmox kernel remains)
8. Updates GRUB and reboots into the Proxmox kernel

## Usage

### Option 1: GitHub Actions (recommended)

Add the following secret in **Settings > Secrets and variables > Actions > Secrets**:

| Secret | Description |
|---|---|
| `ROOT_SSH_PRIVATE_KEY` | SSH private key for root access to the server |

Then go to **Actions > Setup Proxmox VE > Run workflow** and fill in:

| Input | Description | Example |
|---|---|---|
| `server_ip` | IP address of the Debian server | `192.168.1.10` |
| `proxmox_hostname` | FQDN for the Proxmox node | `pve.example.com` |
| `ssh_port` | SSH port (default `22`) | `22` |

After the workflow completes, the web UI is available at:

```
https://<server_ip>:8006
```

### Option 2: Run locally

```sh
ansible-playbook -i "<SERVER_IP>," proxmox/ansible/install-proxmox.yml \
  -u root --private-key ~/.ssh/id_rsa \
  --extra-vars "proxmox_hostname=pve.example.com"
```

Replace `<SERVER_IP>` and the hostname with your actual values.

## Notes

- The playbook uses the **no-subscription** Proxmox repository. This is suitable for home labs and development. For production, use a valid Proxmox subscription and the enterprise repository.
- A reboot is performed at the end to boot into the Proxmox kernel. The playbook waits up to 5 minutes for the server to come back.
- The server must be reachable on port `8006` after the reboot (ensure any firewall allows this).
