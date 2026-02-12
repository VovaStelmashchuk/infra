# Setup ubunut VPS or the docker Installation Playbook

This Ansible playbook installs Docker CE (Community Edition) on Ubuntu machines without Docker Compose, as it's designed for use with Docker Swarm.

## Prerequisites

- Ansible installed on your control machine
- SSH access to target Ubuntu servers
- Sudo privileges on target servers

## Usage

### Option 1: GitHub Actions (recommended)

Use the **Setup VPS** workflow from the GitHub Actions UI (`workflow_dispatch`).

Before running, add the following GitHub secrets in **Settings > Secrets and variables > Actions > Secrets**:

| Secret | Description |
|---|---|
| `VPS_SSH_PRIVATE_KEY` | SSH private key for root access to the new VPS |
| `DEPLOY_USER_PUBLIC_KEY` | SSH public key to authorize for the deploy user |

Then go to **Actions > Setup VPS > Run workflow** and provide the VPS IP, SSH port, and deploy user name.

### Option 2: Local script

Run the command in project root and follow the instructions:
```sh
 ./setup_vps/deploy-vps.sh
```

## What the script does

0. Ask all prerequires input values such as server ip, ssh key for deploy and ssh port
1. Updates the apt cache
2. Installs required packages (curl, gnupg, etc.)
3. Adds Docker's official GPG key
4. Adds Docker's official repository
5. Installs Docker CE
6. Starts and enables the Docker service
7. Creates a dedicated `deploy` user for deploy operations
8. Sets up SSH directory for the deploy user

The playbook creates a dedicated 'deploy' user that:
- Has access to Docker commands without sudo
- Is specifically designed for deployment operations
- Has a home directory at `/home/deploy`

## Docker Swarm Setup

I am personal use the docker swarm with only one manager node just for docker as services. It's just make life easier and deloy smoth.

Once Docker is installed, you can initialize Docker Swarm on your manager node:

```bash
docker swarm init
```

(Optional) And join worker nodes to the swarm:

```bash
docker swarm join --token <token> <manager-ip>:2377
``` 