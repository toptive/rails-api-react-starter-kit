# Shared products server

Operator runbook, adapted from the Phoenix kit and helperflow. These commands provision a
**new** host; inspect an existing shared host first and skip infrastructure that already
exists. Agents do not run this runbook on a server as part of template setup.

One Docker network (`kamal`), one shared PostgreSQL 17 instance, one loopback registry and
one kamal-proxy serve several products. Use the selected Toptive host and a
`<product>.toptive.dev` subdomain. `CHANGE_ME_SERVER_IP` is deliberately not tied to the
Phoenix kit's DigitalOcean IP or another project's Hetzner IP.

## 1. DNS and firewall

Point each product's A record to the selected server. Add AAAA only if IPv6 is configured.
With Cloudflare, use DNS only for the first certificate; if proxying later, use Full (strict).
For `toptive.dev`, use the zone's DNS provider. Never repoint another product's record.

Allow inbound TCP 80/443. Restrict SSH 22 to operator addresses and keys. Do not expose
Postgres (5432) or the registry (5000) publicly. Apply a cloud firewall as well as host
rules; Docker port publishing can bypass ordinary UFW rules.

## 2. Base system

On a fresh Ubuntu host, after confirming key-based SSH in a second session:

```sh
ssh root@CHANGE_ME_SERVER_IP
apt update && apt -y full-upgrade
apt -y install unattended-upgrades fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

# Only when no swap file exists. Swap is a safety net, not app capacity.
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
sysctl --system

printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/00-keys-only.conf
sshd -t && systemctl reload ssh

curl -fsSL https://get.docker.com | sh
docker network create kamal
```

Record `docker network inspect kamal`'s subnet in each app's `TRUSTED_PROXY_CIDRS`. The
shared network is an operational trust boundary: do not run untrusted containers on it.

## 3. Loopback registry and builder

helperflow uses an on-server registry at **127.0.0.1:5000**. That address is intentional:
`localhost` triggers Kamal's laptop registry tunnel instead. Do not replace the host's
existing registry if it serves other products.

```sh
docker run -d --name registry --restart unless-stopped \
  -p 127.0.0.1:5000:5000 -v registry_data:/var/lib/registry registry:2
```

On the operator's laptop, create the native amd64 builder once, using the actual IP in
all three places. The name follows Kamal's remote-builder convention:

```sh
docker context create kamal-remote-ssh---root-CHANGE_ME_SERVER_IP-context \
  --docker host=ssh://root@CHANGE_ME_SERVER_IP
docker buildx create --name kamal-remote-ssh---root-CHANGE_ME_SERVER_IP \
  --driver-opt network=host kamal-remote-ssh---root-CHANGE_ME_SERVER_IP-context
docker buildx inspect kamal-remote-ssh---root-CHANGE_ME_SERVER_IP --bootstrap
```

In the builder **name**, replace dots in the IP with dashes, matching the name derived by
Kamal. The SSH URI still uses dots. `network=host` lets BuildKit push to the loopback registry.
`config/deploy.yml` points `builder.remote` to the same host. A remote build competes with
running apps; serialize heavy builds and move the builder to a dedicated amd64 machine if
capacity is tight. Avoid emulated native-gem builds on an Apple-silicon laptop for deploys.

## 4. Shared Postgres 17

Reuse the existing shared instance. On a new server only, create a root-readable password
file without printing it, then start the database:

```sh
install -d -m 700 /opt/postgres
(umask 077; openssl rand -hex 32 > /opt/postgres/superuser_password)
docker run -d --name postgres --restart unless-stopped --network kamal \
  --memory 1200m -p 127.0.0.1:5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  -v /opt/postgres/superuser_password:/run/secrets/pg:ro \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/pg postgres:17 \
  -c shared_buffers=512MB -c effective_cache_size=1GB -c work_mem=4MB \
  -c maintenance_work_mem=64MB -c max_connections=100
```

Apps connect to `postgres:5432` over `kamal`. Loopback publishing is for operator SSH tunnels
only. Do not publish on `0.0.0.0`. PostgreSQL major upgrades require a tested dump/restore or
upgrade procedure; do not change the image tag against the existing volume.

## 5. Product role and databases

Use one login role per app, with no superuser or role/database creation permissions.
This Rails kit declares four databases; the primary also owns runtime Solid Queue tables.
The legacy queue declaration still needs preparation. This is the Rails-specific departure
from the Phoenix runbook's single database per app; see [DEPLOY.md](DEPLOY.md#database-and-workers).

After `bin/rename`, the following identifiers match `config/database.yml`. Run in psql:

```sh
docker exec -it postgres psql -U postgres
```

```sql
CREATE ROLE starter_kit LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
\password starter_kit
CREATE DATABASE starter_kit_production OWNER starter_kit;
CREATE DATABASE starter_kit_production_cache OWNER starter_kit;
CREATE DATABASE starter_kit_production_cable OWNER starter_kit;
CREATE DATABASE starter_kit_production_queue OWNER starter_kit;
REVOKE CONNECT ON DATABASE starter_kit_production FROM PUBLIC;
REVOKE CONNECT ON DATABASE starter_kit_production_cache FROM PUBLIC;
REVOKE CONNECT ON DATABASE starter_kit_production_cable FROM PUBLIC;
REVOKE CONNECT ON DATABASE starter_kit_production_queue FROM PUBLIC;
```

Use a fresh password through the hidden psql prompt and store that same value locally with
`cred add` as `starter_kit/STARTER_KIT_DATABASE_PASSWORD`. Never echo it, put it in shell
history or share it in chat. `citext` and `pgcrypto` are trusted extensions installed by the
app's schema as database owner. Repeat isolation for every product's databases, not just the
new app. Before deploying, verify the role can connect to its databases and cannot connect
to another product's databases. Back up before changing privileges on an existing server.

## 6. Backups and restore

Enable provider snapshots plus nightly logical dumps of **all** product databases to a
private object-storage backup bucket. Snapshots restore a host; dumps restore one database.
Use a bucket-scoped credential, configure the S3 client without logging credentials, and
keep 30 days of dumps. Do not reuse an upload bucket's credentials.

Example after installing the MinIO `mc` client and configuring a `backups` alias securely:

```sh
cat > /usr/local/bin/pg-backup <<'SH'
#!/usr/bin/env bash
set -euo pipefail
stamp=$(date -u +%Y%m%dT%H%M%SZ)
while IFS= read -r database; do
  docker exec postgres pg_dump -U postgres -Fc "$database" |
    mc pipe "backups/CHANGE_ME_BACKUP_BUCKET/products/$database/$stamp.dump"
done < <(docker exec postgres psql -U postgres -Atc \
  "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'")
SH
chmod 700 /usr/local/bin/pg-backup
mc ilm rule add --expire-days 30 backups/CHANGE_ME_BACKUP_BUCKET
echo '15 7 * * * root /usr/local/bin/pg-backup >> /var/log/pg-backup.log 2>&1' > /etc/cron.d/pg-backup
```

Alert on backup failures and stale/missing objects. Save roles separately or retain the
role provisioning procedure. Test restore into a scratch database with the same PostgreSQL
major version:

```sh
docker exec postgres createdb -U postgres starter_kit_restore
mc cat backups/CHANGE_ME_BACKUP_BUCKET/products/starter_kit_production/CHANGE_ME_TIMESTAMP.dump \
  | docker exec -i postgres pg_restore --exit-on-error --no-owner --no-privileges -U postgres -d starter_kit_restore
# Verify counts, constraints and representative reads before dropping the scratch DB.
docker exec postgres dropdb -U postgres starter_kit_restore
```

Never test restores against the live app database. Back up the local storage volume too if
using it; private product uploads normally reside in their own S3 bucket.

## 7. Product upload bucket

Create a private bucket and a dedicated access key limited to it. In `config/deploy.yml`, set
`S3_BUCKET`, `S3_ENDPOINT` and `S3_REGION` (Spaces signing region `us-east-1`), then enable
`S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` in `env.secret` and `.kamal/secrets`. Store the
values with `cred add`. Configure CORS for the exact SPA origin, PUT/GET/HEAD and Content-Type;
keep public listing and public ACLs disabled. Signed downloads still require API authorization.

## 8. Deploy and monitor

Follow [DEPLOY.md](DEPLOY.md) for `cred exec ... -- bundle exec kamal setup`, boot order and
verification. Never run `bin/setup` or seeds on production. Inspect `/health`, sign-in, jobs,
uploads and mail after first deploy; keep `SITE_INDEXING=0` and signup closed/invite until ready.

For a 4 GB host, reserve roughly 1.2 GB for Postgres plus OS/proxy/registry overhead. Measure
Rails with its queue supervisor and actual workload; do not assume the Phoenix per-app RSS
estimate applies. The 400 MB app cap is a limit, not a capacity forecast. Count all primary,
cache, Cable, job and migration connections against Postgres's maximum.

Use provider graphs and `docker stats --no-stream`; alert on memory above 85%, disk above 80%,
backup failures and failing health probes. Configure Sentry per product. Never tear down the
shared proxy, registry, network or PostgreSQL while removing one product.
