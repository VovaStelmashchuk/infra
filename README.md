# Infra for pet project

We build real **uncloud** here.

The project with all scripts for setup an infrastructure for simple pet project, without over engineering, but with all required components, such as backups for database, backup for reverse proxy etc.

The project prepares VPS for hosting docker stack by Ansible scripts. All infrastructure components deploy as docker services. Also configuration provides presetup docker networks. 

So basicly you just rent any VPS or setup the ubunut server your self, and have it up and running for few minutes.

The project provides all infrastruture require to implement simple pet projects without over engineering. All setup of VPS done with infrastructure as code approatch which help you replicate the infra on any ubuntu server without pain.

The infrastructure includes the following:
- Docker Swarm
- MongoDB replica set
- PostgreSQL with pgAdmin
- Caddy reverse proxy
- Grafana
- Centralized logs for every container (Loki + Grafana Alloy)
- Periodic backups for mongo, postgres, grafana, caddy config

## Infrastructure components

### Reverse proxy

The project provides **caddy** as reverse proxy for handle SSL key generation and allow you to host few services on one VPS.

### Database

MongoDB is my database of choice. I believe it's the only data store which you need to build the project.
I use the mongodb bucket for BLOB store, it make local infracture easy to handle, and the API for mongo bucket easy to work compare to S3 buckets.

MongoDB run in replica set with one node, the solution allow to use all mongo replica set feature as watch the collection.

Generate key for replica set (execute on server mathine)

```sh
openssl rand -base64 756 | docker secret create mongodb-keyfile -
```

#### PostgreSQL

Some projects need a relational store, so the stack also runs **postgres** next to
mongo. It is a single instance, no replication, one `postgres-data` volume. The
service is deployed with `replicas: 1` and `update_config.order: stop-first` so two
containers never touch the same data directory.

The root user is the same `${USERNAME}` / `${PASSWORD}` pair used by mongo and
grafana. Applications reach it on the private `postgres-net` overlay network:

```
postgresql://${USERNAME}:${PASSWORD}@postgres:5432/postgres
```

Note for postgres 18: the image keeps `PGDATA` in `/var/lib/postgresql/18/docker`,
so the volume is mounted at `/var/lib/postgresql`, not at `.../data` as in older
versions.

**pgadmin** (`dpage/pgadmin4`) is published through caddy on
`pgadmin.stelmashchuk.dev`, same idea as compass for mongo. pgAdmin only accepts an
email as the login, so the account is `${USERNAME}@stelmashchuk.dev` with the shared
`${PASSWORD}`. The postgres server is not preregistered in pgAdmin, add it once with
host `postgres`, port `5432` and the credentials above; it is then stored in the
`pgadmin-data` volume.

### Logs

All container logs of the swarm are collected and browsable in Grafana, so there is
no need to ssh into the VPS and run `docker service logs` anymore.

Three services do the job:

- **alloy** (`grafana/alloy`) runs in `global` mode, so one instance per swarm node.
  It reads the Docker API, discovers every running container on its node and streams
  the container stdout/stderr to Loki. Config: `alloy/config.alloy`.
- **loki** (`grafana/loki`) stores the logs on the `loki-data` volume. It is a single
  node, filesystem backed setup, no object storage, no clustering. Config:
  `loki/loki-config.yml`.
- **loki-init** is a one-shot task (like `mongo-rs-init`) that prepares the data
  directories on the `loki-data` volume for uid `10001`. The loki image is
  distroless and cannot chown its own volume.

They live on the private `logs-net` overlay network together with Grafana. Loki is
**not** published through Caddy, the only way to read the logs is Grafana.

#### How to look at the logs

Open [grafana.stelmashchuk.dev](https://grafana.stelmashchuk.dev) and either:

- use the dashboard **Service logs** (provisioned from
  `grafana/dashboards/service-logs.json`) - pick a stack, a service and a node,
  optionally type a regex into the search box, or
- use **Explore** with the `Loki` datasource and write LogQL by hand.

Useful queries:

```logql
# everything of one service
{service="infra_grafana"}

# everything of the infra stack, only the lines containing "error"
{stack="infra"} |~ "(?i)error"

# how many lines per second each service produces
sum by (service) (rate({stack="infra"}[5m]))
```

Every log line carries three labels:

| label     | meaning                                                              |
| --------- | -------------------------------------------------------------------- |
| `service` | swarm service name (`infra_grafana`), or container name if not swarm |
| `stack`   | stack the service belongs to (`infra`, `mixdrinks`, ...)             |
| `node`    | swarm node the container runs on                                     |

The label set is kept small on purpose: each unique combination is a separate stream
in Loki, and high cardinality labels (container id, request id, ...) are what makes
Loki slow and expensive. Everything else stays in the log line and can be filtered
with `|=` / `|~`.

#### Retention

Logs are kept **30 days** and then deleted by the Loki compactor, see
`retention_period` in `loki/loki-config.yml`. Logs are not backed up - they are
debugging material, not data we need to restore.

### Periodic tasks

The `infra` stack has the cron executor `crazymax/swarm-cronjob` which is used for periodic backup database and caddy config

### Backups

The project provides periodic backups for mongo, postgres and caddy config.
The Database backups each hour, each day, and each week, all backups can be stored in any S3 compatible storage.

Postgres is backed up **weekly only** (`postgres-backup-weekly`, Tuesday 03:40 UTC).
The job runs `pg_dumpall` and uploads one gzipped sql file to the `postgres-weekly`
folder of the S3 bucket, see `postgres-backup/backup.sh`.

## Build & deploy

For more details, take a look at [project github action](https://github.com/VovaStelmashchuk/infra/tree/main/.github/workflows)

You can find all required environment variables and secrets for the project in the github action job `Create env file`. Also some secrets are provided as docker secrets, but I have been trying to get rid of docker secrets in the project.

## Local development

For local infrastructure use file `docker-stack.local.yml` - the file setup only mongo and mongo viewer

The setup is tested only for MacOS with `colima`

1. Start colima by command

In case `qemu` is not installed on your machine, install it by command `brew install qemu`

```bash
colima start --network-address
```

2. Verify colima status

```bash
colima status
```

The command will return information about colima virtual machine, look to the line `INFO[0000] address:`
Use the colima VM IP address to start the docker stack

```bash
docker swarm init --advertise-addr <IP address from the colima status command>
```

3. Run docker stack

```bash
docker stack deploy -c docker-stack.local.yml infra
```

The command will start the mongodb at port 27017 and mongo viewer on port 5000 into colima VM.

Open http://<colima ip>:5000 to browse the mongo db.

4. (Optional) Apply backup/snapshot of mongodb to your local environment

Copy mongo backup file into docker container

```bash
docker cp /path/to/backup/test.archive mongo:/test.archive
```

Restore mongo from backup

```bash
docker exec -it <mongo container> mongorestore --uri mongodb://localhost:27017 --gzip --archive=test.archive
```

### Restore postgres from backup

```sh
gunzip -c pgdumpall-2026-08-25_03-40.sql.gz | \
  psql --dbname="postgresql://<user>:<password>@localhost:5432/postgres"
```

`pg_dumpall` output includes the roles and every database, so a single file restores
the whole instance.

### Restore database from backup

```
mongorestore \
  --host 167.235.52.168 \
  --port 2017 \
  --username <root_user_name> \
  --password '<pass for root>' \
  --authenticationDatabase admin \
  --drop \
  --gzip \
  --archive=backup-15-00.gz
```

### Local mongo, restore from any backup file

```
mongorestore --uri="mongodb://0.0.0.0:27017/" --drop --gzip --db=mixdrinks --archive=hourly_mongodump-2025-05-29_13-00.gz
```

## Local infrastructure

For the local infrastructure use the `docker-stack.local.yml`. This stack sets up a MongoDB Replica Set environment useful for local testing.

### Services

- **mongo-rs-1**: The primary MongoDB service running version 8.2.3.
- **mongo-rs-init**: An oversized ephemeral container that waits for `mongo-rs-1` to be ready and initializes the Replica Set (`rs0`).
- **mongo-rs-viewer**: A web-based MongoDB viewer (`haohanyang/compass-web`) exposed on port **5001**.

### Usage

To deploy the local stack:

Add `192.168.64.2 mongo-rs-1` into `/etc/hosts` file

```sh
node local_deploy.js
```

Once deployed, you can access the MongoDB viewer at `http://<colima_ip>:5000`.
Credentials for the viewer can be set in your environment variables (`USERNAME`, `PASSWORD`) or will default if not specified in the stack file (check `docker-stack.local.yml` for variable usage).


### Grafana backup restore

```sh
docker service scale infra_grafana=0
```

```sh
docker run --rm \
  -v infra_grafana-data:/data \
  -v "$(pwd)":/backup \
  alpine \
  sh -c "cp /backup/grafana.db /data/grafana.db"
```

```sh
docker run --rm \
  -v infra_grafana-data:/data \
  alpine \
  chown 472:472 /data/grafana.db
```

To create own infrastructure setup, fork the repository and update all need github action secrets and variables.
