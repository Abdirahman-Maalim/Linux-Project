# Linux Administration Project

A documented Linux web environment: users and groups with least-privilege permissions, an
original validation script, an NGINX static site deployment, and three troubleshooting cases.

**Author:** Abdirahman Maalim
**Original deployment:** 2026-07-01 | **Rebuilt from scratch:** November 2026

---

## 1. Environment overview

| Item | Value |
|------|-------|
| Operating system | Ubuntu 26.04 LTS (virtual machine, hostname `ubuntu-vm`) |
| Web server | NGINX 1.28.3 (Ubuntu package), managed by systemd |
| Project root | `/opt/linuxproject` |
| Web root | `/var/www/linuxproject/html` |
| Access method | Local: `curl http://localhost/` |

The VM was cleaned before the rebuild: the old NGINX package (purged), old project directory,
old user and old group were removed so the project started from a known state.

## 2. Repository structure

~~~
Linux-Project/
├── README.md                 Project report (this file)
├── scripts/health-check.sh   Validation script (Milestone 2)
├── config/linuxproject.conf  NGINX site configuration
├── site/                     Deployed website: index.html, styles.css, about.html
├── docs/troubleshooting.md   Detailed troubleshooting cases (Milestone 4)
└── evidence/                 Text logs of real command output
~~~

On the server the same layout is deployed as:

~~~
/opt/linuxproject/{scripts,config,docs,logs,reports}
/var/www/linuxproject/html
~~~

## 3. Users, groups and permissions (Milestone 1)

### Design

| Type | Name | Purpose |
|------|------|---------|
| Group | `webteam` | Maintainers: may edit site files, scripts and config |
| Group | `webaudit` | Reviewers: read-only access to logs and reports |
| User | `webadmin` | Site maintainer, member of `webteam` |
| User | `auditor` | Reviewer, member of `webaudit` only |

Both users have no password set, so direct login is locked. Work is done with
`sudo -u webadmin ...`, which avoids shared passwords.

### Ownership and permissions

| Path | Owner:Group | Mode | Reason |
|------|-------------|------|--------|
| `/opt/linuxproject` | root:root | 755 | Everyone can enter; only root changes the root |
| `scripts`, `docs` | webadmin:webteam | 2775 | Team edits, others read |
| `config` | webadmin:webteam | 2770 | Server settings: team only |
| `logs`, `reports` | webadmin:webaudit | 2750 | Admin writes, auditors read, others blocked |
| `/var/www/linuxproject`, `html` | webadmin:webteam | 2775 | Team edits; NGINX reads as "other" |
| Site files | webadmin:webteam | 664 | Team edits; NGINX (www-data) can read |

The leading `2` is the setgid bit: new files inherit the directory's group, so ownership
stays consistent without manual fixes.

### Commands used

~~~bash
sudo groupadd webteam
sudo groupadd webaudit
sudo useradd -m -s /bin/bash -G webteam webadmin
sudo useradd -m -s /bin/bash -G webaudit auditor
sudo mkdir -p /opt/linuxproject/{scripts,config,docs,logs,reports} /var/www/linuxproject/html
~~~

### Verification

[`evidence/01-users-groups-permissions.log`](evidence/01-users-groups-permissions.log) shows the
groups, users, ownership and four access tests:

| Test | Expected | Result |
|------|----------|--------|
| `webadmin` writes to `scripts` | allowed | OK |
| `auditor` reads `logs` | allowed | OK |
| `auditor` writes to `logs` | denied | Permission denied |
| `auditor` reads `config` | denied | Permission denied |

`webadmin` is also allowed exactly one privileged command, the NGINX configuration test, through
`/etc/sudoers.d/webadmin-nginx` (validated with `visudo -cf`):

~~~
webadmin ALL=(root) NOPASSWD: /usr/sbin/nginx -t
~~~

## 4. Shell script (Milestone 2)

**File:** [`scripts/health-check.sh`](scripts/health-check.sh), installed to
`/opt/linuxproject/scripts/` with owner `webadmin:webteam` and mode 775.

### What it does

It audits the whole environment and reports `PASS`, `WARN` or `FAIL` for each check:

1. Users, groups and group memberships exist.
2. Every project directory has the expected owner, group and mode.
3. NGINX is installed, active, enabled at boot, its configuration passes `nginx -t`, and port 80
   has a listener.
4. Site files exist and each page returns HTTP 200.

It writes a timestamped log to `/opt/linuxproject/logs`, copies it to
`/opt/linuxproject/reports/latest-report.txt` (readable by the auditor), and exits with `1` if any
check fails, so it can be used in automation.

### Required scripting concepts

| Requirement | Where used |
|-------------|------------|
| Shebang | `#!/usr/bin/env bash` |
| Comments | Header block and one per function |
| Variables | `PROJECT_DIR`, `WEB_ROOT`, `LOG_FILE` and others |
| Conditionals | `if` and `case` in every check |
| Loops and functions | `for` loops over users, groups and directories; four check functions |
| Useful output | PASS/WARN/FAIL lines, summary, log and report files |
| Executable permissions | Mode 775 |

### Execution evidence

- First run, before NGINX was installed: [`evidence/02-health-check-before-nginx.log`](evidence/02-health-check-before-nginx.log).
- After deployment and troubleshooting: **23 passed, 0 warnings, 0 failed**
  ([`evidence/08-final-validation.log`](evidence/08-final-validation.log)).

Running the same script at both stages shows it reports the real state of the environment.

## 5. NGINX deployment (Milestone 3)

### Steps

1. Installed NGINX with `sudo apt install -y nginx`
   ([`evidence/03-nginx-install.log`](evidence/03-nginx-install.log)).
2. Placed the provided `index.html` and `styles.css` in `/var/www/linuxproject/html` using
   `install -o webadmin -g webteam -m 664`.
3. Wrote the site configuration ([`config/linuxproject.conf`](config/linuxproject.conf)):

   ~~~nginx
   server {
       listen 80;
       listen [::]:80;
       server_name _;

       root /var/www/linuxproject/html;
       index index.html;

       access_log /var/log/nginx/linuxproject.access.log;
       error_log  /var/log/nginx/linuxproject.error.log;

       location / {
           try_files $uri $uri/ =404;
       }
   }
   ~~~

4. Enabled it with a symlink from `sites-available` to `sites-enabled` and removed the default
   site so only one site answers on port 80.
5. Validated, then reloaded only on success: `sudo nginx -t && sudo systemctl reload nginx`.

Static file changes need no reload, because NGINX reads files from disk on each request. A reload
is only required when the configuration changes.

### Website customization

The page header and a new "Deployment Details" card show the student name, hostname, original
deployment date (2026-07-01), rebuild date, document root and maintaining user. The "Student Task"
card describes the user and group design. An additional `about.html` page was added.

## 6. Validation

[`evidence/08-final-validation.log`](evidence/08-final-validation.log) and
[`evidence/04-nginx-deployment-validation.log`](evidence/04-nginx-deployment-validation.log) show:

- NGINX installed, active and enabled; `nginx -t` successful
- A single listener on port 80
- `/`, `/styles.css` and `/about.html` all returning HTTP 200
- Customization visible in the served HTML
- Health check passing with exit code 0

Local access was verified with `curl` against `http://localhost/` over IPv4. IPv6 loopback
(`[::1]`) gave no response on this VM; NGINX is configured to listen on both, and IPv4 is
sufficient for the project's local-access requirement.

## 7. Troubleshooting cases (Milestone 4)

Full details, with commands, output, fix and verification, are in
[`docs/troubleshooting.md`](docs/troubleshooting.md).

| # | Problem | Root cause | Fix |
|---|---------|------------|-----|
| 1 | Default NGINX page served | Site never enabled; `default` still active | Enable `linuxproject`, remove `default`, `nginx -t`, reload |
| 2 | Page unstyled (CSS 404) | `styles.css` missing from the web root | Deploy the file with correct owner and mode |
| 3 | `about.html` returns 403 | File created with `umask 077` (mode 600); `www-data` cannot read it | `chmod 664` |

## 8. Lessons learned and improvements

**What I learned**

- A passing `nginx -t` only proves the syntax is valid, not that the right site is active.
  `nginx -T` shows what is really loaded.
- The error log and a test as the service user (`sudo -u www-data`) find permission problems
  faster than guessing.
- A reload is asynchronous: confirm with the access log or a short wait before concluding a fix
  failed.
- Directory setgid bits and consistent modes keep a multi-user web root maintainable.
- Evidence kept as text logs is easier to review than screenshots.

**What I would improve in production**

- Serve over HTTPS with a certificate and redirect HTTP to HTTPS.
- Enable a host firewall (for example `ufw`) allowing only the needed ports.
- Rotate the project logs with `logrotate` and run the health check on a schedule with a
  notification on failure.
- Keep the configuration and site in version control with a deployment script, instead of
  copying files by hand.
- Add security headers and disable the NGINX version banner (`server_tokens off`).

## 9. Requirement checklist

| Requirement | Where |
|-------------|-------|
| Prepared Linux environment and organized directory structure | Sections 1-3 |
| Additional user and group used meaningfully | Section 3 |
| Correct ownership and permissions, verified | Section 3, evidence 01 |
| Original shell script with required concepts | Section 4, `scripts/health-check.sh` |
| NGINX installed and configured by me | Section 5, `config/linuxproject.conf` |
| Provided site deployed and customized | Section 5, `site/` |
| Configuration validated before reload | Section 5, evidence 04 |
| Validation evidence | Section 6, evidence 04 and 08 |
| At least three troubleshooting cases | Section 7, `docs/troubleshooting.md` |
| Report with overview, users/groups, script, deployment, validation, troubleshooting, lessons | This file |
