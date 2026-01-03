# Portano Deployment Script

Advanced deployment automation for SvelteKit applications with release management and shared resource symlinking.

## Overview

Portano is a deployment script that implements a release-based deployment strategy with automatic rollback capabilities. It maintains multiple releases on the server, symlinks shared directories for data persistence, and provides easy rollback to previous versions.

### Key Features

- Zero-downtime deployments with atomic symlink switching
- Automatic release history management (keeps last 10 releases)
- Shared directory management for persistent data
- Separate build and deploy stages for flexible workflows
- SSH-based secure deployment
- Rsync-powered efficient file transfers

## Prerequisites

### Local Requirements

- Node.js and npm installed
- SSH access to remote server
- rsync installed locally

### Remote Server Requirements

- SSH server running
- Proper SSH key authentication configured
- Write permissions to deployment directory
- rsync installed on server

## Configuration

### Script Variables

Edit the configuration section in `deploy.sh`:

```bash
# Configuration
REMOTE_USER="user"
REMOTE_HOST="example.com"
DEPLOY_PATH="/home/domains/podcast.example.com"
RELEASES_PATH="${DEPLOY_PATH}/releases"
CURRENT_LINK="${DEPLOY_PATH}/current"
SHARED_PATH="${DEPLOY_PATH}/shared"
CURRENT_ENVIRONMENT="${NODE_ENV:-production}"
# Shared directories to symlink to each release
SHARED_SYMLINKS=(
  "content"
  "uploads"
  "database.db"
)
MAX_RELEASES=10
```

### Configuration Options

| Variable | Description | Example |
|----------|-------------|---------|
| `REMOTE_USER` | SSH username on remote server | `user` |
| `REMOTE_HOST` | Remote server hostname or IP | `example.com` |
| `DEPLOY_PATH` | Base deployment directory | `/home/domains/example.com` |
| `CURRENT_ENVIRONMENT` | Environment name for .env file | `${NODE_ENV:-production}` |
| `SHARED_SYMLINKS` | Array of shared directories/files | `("content" "uploads" "database.db")` |
| `MAX_RELEASES` | Number of releases to keep | `10` |

### Environment Variable Configuration

The script uses `CURRENT_ENVIRONMENT` variable (defaults to `$NODE_ENV` or "production") to manage environment-specific configuration files:

- Local file: `.env.${CURRENT_ENVIRONMENT}` (e.g., `.env.production`, `.env.staging`)
- Synced to: `shared/.env.${CURRENT_ENVIRONMENT}` on server
- Symlinked as: `.env` in each release

This allows different environments to have separate configurations while maintaining them across deployments.

## Directory Structure

After deployment, the remote server will have this structure:

```
/home/domains/example.com/
├── current -> releases/20260103143022/    # Symlink to active release
├── releases/
│   ├── 20260103143022/                    # Current release
│   │   ├── index.js
│   │   ├── package.json
│   │   ├── .env -> ../../shared/.env.production            # Symlink
│   │   ├── content -> ../../shared/content                 # Symlink
│   │   ├── uploads -> ../../shared/uploads                 # Symlink
│   │   └── database.db -> ../../shared/database.db         # Symlink (file)
│   ├── 20260103120815/                    # Previous release
│   └── 20260103101234/                    # Older release
└── shared/
    ├── .env.production                    # Persistent environment config
    ├── content/                           # Persistent podcast content (directory)
    ├── uploads/                           # Persistent file uploads (directory)
    └── database.db                        # Persistent database file
```

### Release Naming

Releases are named using timestamp format: `YYYYMMDDHHMMSS`

Example: `20260103143022` = January 3, 2026 at 14:30:22

## Usage

### Getting Help

Run the script without arguments to see usage information and the remote folder structure:

```bash
./deploy.sh
```

**Output:**
```
Portano Deployment Script

Usage: ./deploy.sh [command]

Commands:
  init    - Initialize remote directory structure (first-time setup)
  build   - Build the application locally only
  deploy  - Deploy existing build to server (skips build step)
  all     - Build and deploy

Examples:
  ./deploy.sh init     # Initialize remote server structure
  ./deploy.sh all      # Build and deploy
  ./deploy.sh build    # Build only
  ./deploy.sh deploy   # Deploy only

Remote Folder Structure:

/home/domains/example.com/
├── current -> releases/YYYYMMDDHHMMSS/    # Symlink to active release
├── releases/
│   ├── 20260103143022/                    # Current release
│   │   ├── index.js
│   │   ├── package.json
│   │   ├── .env -> ../../shared/.env.production
│   │   ├── content -> ../../shared/content
│   │   ├── uploads -> ../../shared/uploads
│   │   ├── database.db -> ../../shared/database.db
│   ├── 20260103120815/                    # Previous release
│   └── 20260103101234/                    # Older release
└── shared/
    ├── .env.production                    # Environment config
    ├── content/
    ├── uploads/
    ├── database.db                              # File
```

### First-Time Setup: Initialize Remote Structure

Before deploying for the first time, initialize the directory structure on the remote server:

```bash
./deploy.sh init
```

**Steps executed:**
1. Create base deployment directories
2. Create releases directory
3. Create shared directory
4. Create shared subdirectories (only directories, not files)

**Output example:**
```
==> Initializing remote directory structure...
==> Target: example.com:/home/domains/example.com

==> ✓ Directory structure initialized

Created directories:
  - /home/domains/example.com/releases
  - /home/domains/example.com/shared
  - /home/domains/example.com/shared/content/
  - /home/domains/example.com/shared/uploads/

Note: Files (like database.db) will be created during first deployment

==> Server is ready for deployments
```

**Note:** The init command only creates directories. Files in `SHARED_SYMLINKS` (like `database.db`) are created/synced during the first actual deployment when they exist locally.

### Complete Build and Deploy

Build the application and deploy to server in one command:

```bash
./deploy.sh all
```

**Steps executed:**
1. Install dependencies (`npm install`)
2. Build application (`npm run build`)
3. Create remote directory structure
4. Upload application files
5. Upload static files
6. Sync shared directories
7. Create symlinks for shared resources
8. Update current release symlink
9. Clean up old releases

### Build Only

Build the application without deploying:

```bash
./deploy.sh build
```

**Use case:** Test build locally before deploying or prepare build for later deployment.

### Deploy Only

Deploy an existing build without rebuilding:

```bash
./deploy.sh deploy
```

**Use case:** Quickly redeploy after fixing deployment configuration or when build already exists.

**Requirement:** `build/` directory must exist from previous build.

## Shared Paths Management

### What Are Shared Paths?

Shared paths are directories or files that persist across deployments. Instead of copying these to each release, they're stored once in the `shared/` directory and symlinked to each release.

### Default Shared Paths

1. **content** - Application data and configuration
2. **uploads** - User-uploaded files
3. **database.db** - SQLite database file (if using file-based database)

### Adding New Shared Paths

To add a new shared directory/file:

1. Edit the `SHARED_SYMLINKS` array in `deploy.sh`:

```bash
SHARED_SYMLINKS=(
  "content"
  "uploads"
  "database.db"
  "logs"           # New addition
  "cache"          # New addition
)
```

2. Deploy - the script will automatically:
   - Create the directory on the server in `shared/`
   - Sync local version if it exists
   - Create symlink in each new release

### Shared Path Behavior

- **If path exists locally:** Synced to server via rsync
- **If path doesn't exist locally:** Skipped with info message
- **On server:** Created as directory in `shared/` and symlinked to release

## Environment File Management

The script automatically manages environment-specific configuration files using the `CURRENT_ENVIRONMENT` variable.

### How It Works

1. **Environment Detection:**
   - Uses `$NODE_ENV` environment variable if set
   - Falls back to "production" if not set
   - Can be overridden: `CURRENT_ENVIRONMENT="staging"`

2. **Sync Process:**
   - Looks for `.env.${CURRENT_ENVIRONMENT}` file locally (e.g., `.env.production`)
   - If found, syncs to `shared/.env.${CURRENT_ENVIRONMENT}` on server
   - If not found locally, skips sync (preserves existing server file)

3. **Symlink Creation:**
   - If `shared/.env.${CURRENT_ENVIRONMENT}` exists on server
   - Creates symlink: `release/.env -> shared/.env.${CURRENT_ENVIRONMENT}`
   - Each release gets the same environment configuration

### Usage Examples

**Deploy to Production:**
```bash
# Uses .env.production locally
./deploy.sh all

# Or explicitly set environment
NODE_ENV=production ./deploy.sh all
```

**Deploy to Staging:**
```bash
# Uses .env.staging locally
NODE_ENV=staging ./deploy.sh all
```

**Deploy to Custom Environment:**
```bash
# Uses .env.development locally
NODE_ENV=development ./deploy.sh all
```

### Multiple Environment Setup

Create separate environment files for each environment:

```bash
.env.production      # Production secrets
.env.staging         # Staging configuration
.env.development     # Development settings
```

Deploy to different environments:

```bash
# First-time: Initialize server
./deploy.sh init

# Deploy to production
NODE_ENV=production ./deploy.sh all

# Deploy to staging (requires separate server config)
# Edit deploy.sh to point to staging server, then:
NODE_ENV=staging ./deploy.sh all
```

### Environment File Best Practices

1. **Never commit .env files to git**
   ```bash
   # Add to .gitignore
   .env*
   !.env.example
   ```

2. **Use .env.example as template**
   ```bash
   # .env.example (safe to commit)
   DATABASE_URL=postgresql://user:pass@localhost:5432/db
   SESSION_SECRET=your-secret-here
   PUBLIC_URL=https://example.com
   ```

3. **First deployment to new environment**
   - Manually create `.env.${ENVIRONMENT}` on server first
   - Or sync from local during first deploy
   - Subsequent deploys preserve existing server file if not present locally

## Example Configurations

### Basic Single Server

```bash
REMOTE_USER="deploy"
REMOTE_HOST="example.com"
DEPLOY_PATH="/var/www/myapp"
SHARED_SYMLINKS=(
  "uploads"
  "database.db"
)
MAX_RELEASES=5
```

### Production Setup with Multiple Shared Resources

```bash
REMOTE_USER="production"
REMOTE_HOST="prod.example.com"
DEPLOY_PATH="/home/apps/myapp"
CURRENT_ENVIRONMENT="${NODE_ENV:-production}"
SHARED_SYMLINKS=(
  "content"
  "uploads"
  "database.db"
  "logs"
  "cache"
  "tmp"
)
MAX_RELEASES=15
```

**Note:** Environment files (`.env.production`, `.env.staging`) are managed automatically by the script and don't need to be in `SHARED_SYMLINKS`.

### Staging Environment

```bash
REMOTE_USER="staging"
REMOTE_HOST="staging.example.com"
DEPLOY_PATH="/home/staging/myapp"
SHARED_SYMLINKS=(
  "uploads"
  "database.db"
)
MAX_RELEASES=3
```

## Deployment Workflow Examples

### First-Time Server Setup

```bash
# 1. Configure deploy.sh with your server details
vim deploy.sh

# 2. Initialize remote directory structure
./deploy.sh init

# Output:
# ==> Initializing remote directory structure...
# ==> Target: example.com:/home/domains/example.com
# ==> ✓ Directory structure initialized
# ...
# ==> Server is ready for deployments

# 3. Deploy application
./deploy.sh all
```

### Standard Production Deployment

```bash
# 1. Pull latest changes
git pull origin main

# 2. Run tests locally
npm test

# 3. Deploy
./deploy.sh all

# Output:
# ==> Building application...
# ==> ✓ Build complete
# ==> Starting deployment to example.com
# ==> Release: 20260103143022
# ...
# ==> ✓ Deployment complete!
```

### Deploy to Staging Environment

```bash
# 1. Ensure .env.staging exists locally
ls .env.staging

# 2. Deploy to staging
NODE_ENV=staging ./deploy.sh all

# Output:
# ==> Managing environment file for: staging
# ==> Syncing .env.staging to shared folder...
# ==> ✓ Environment file synced
# ...
```

### Quick Iteration During Development

```bash
# Build once
./deploy.sh build

# Make configuration changes to deploy.sh
vim deploy.sh

# Deploy without rebuilding
./deploy.sh deploy

# Make more changes
vim deploy.sh

# Deploy again
./deploy.sh deploy
```

### Emergency Rollback

```bash
# SSH to server
ssh user@example.com

# List releases
ls -lt /home/domains/example.com/releases/

# Switch to previous release
cd /home/domains/example.com
ln -sfn releases/20260103120815 current

# Restart application
pm2 restart myapp
```

## Rsync Exclusions

The script automatically excludes these directories from upload:

- `.git` - Git repository data
- `node_modules` - Dependencies (should be installed on server if needed)
- `.svelte-kit` - SvelteKit build cache
- `.claude` - Claude Code configuration
- `content` - Managed as shared path

## Process Management

The script handles deployment but doesn't manage the application process. You need a process manager like PM2, systemd, or Docker.

### Example PM2 Setup

```bash
# On remote server
cd /home/domains/example.com/current
pm2 start npm --name "myapp" -- start
pm2 save
pm2 startup
```

### Example systemd Service

Create `/etc/systemd/system/myapp.service`:

```ini
[Unit]
Description=Application
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/domains/example.com/current
ExecStart=/usr/bin/node index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl enable myapp
sudo systemctl start myapp
```

### Reload After Deployment

Add to your deploy.sh or run manually after deployment:

```bash
# PM2
ssh user@example.com "pm2 reload myapp"

# systemd
ssh user@example.com "sudo systemctl restart myapp"

# Docker
ssh user@example.com "cd /home/domains/example.com && docker-compose up -d --no-deps app"
```

## Troubleshooting

### "Build directory not found"

```
==> ✗ Error: Build directory not found. Run './deploy.sh build' first
```

**Solution:** Run `./deploy.sh build` before `./deploy.sh deploy`

### Permission Denied Errors

```
rsync: permission denied
```

**Solution:** Check SSH key authentication and write permissions on remote server

### Symlink Creation Fails

```
ln: failed to create symbolic link
```

**Solution:** Verify `SHARED_PATH` and `RELEASE_PATH` are correct and accessible

### Application Not Restarting

After deployment, application still serves old version.

**Solution:** Ensure your process manager points to `/current` symlink and restart it after deployment

### Shared Directory Not Syncing

```
==> Skipping uploads (not found locally)
```

**Solution:**
- If directory should exist locally, create it: `mkdir uploads`
- If directory should only exist on server, this message is normal

### Environment File Not Found

```
==> No local .env.production found, skipping sync
```

**Solution:**
- This is normal if environment file already exists on server
- To update environment file, create `.env.${ENVIRONMENT}` locally and redeploy
- Or manually edit file on server at `shared/.env.${ENVIRONMENT}`

### Wrong Environment Deployed

Application uses wrong environment configuration.

**Solution:**
```bash
# Check which environment was deployed
ssh user@example.com "readlink /home/domains/example.com/current/.env"

# Should show: ../../shared/.env.production (or your environment)

# Redeploy with correct environment
NODE_ENV=production ./deploy.sh all
```

### Init Command Fails

```
mkdir: cannot create directory: Permission denied
```

**Solution:**
- Verify SSH user has write permissions to `DEPLOY_PATH`
- Create parent directory manually: `ssh user@host "mkdir -p /home/domains/example.com"`
- Check that `DEPLOY_PATH` is correct in deploy.sh

## Best Practices

### SSH Key Authentication

Set up passwordless SSH for smoother deployments:

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "deploy@example.com"

# Copy to server
ssh-copy-id user@example.com
```

### Pre-Deployment Checklist

- [ ] Run tests locally
- [ ] Review changes in git
- [ ] Verify correct environment (check `$NODE_ENV`)
- [ ] Ensure `.env.${ENVIRONMENT}` exists if updating configuration
- [ ] Verify database migrations (if any)
- [ ] Backup database before major changes
- [ ] For first deployment: Run `./deploy.sh init` first
- [ ] Monitor logs after deployment

### Post-Deployment Verification

```bash
# Check application status
ssh user@example.com "pm2 status"

# Check logs
ssh user@example.com "pm2 logs myapp --lines 50"

# Verify site is accessible
curl -I https://example.com

# Check current release
ssh user@example.com "readlink /home/domains/example.com/current"

# Verify environment file symlink
ssh user@example.com "readlink /home/domains/example.com/current/.env"

# Verify all symlinks
ssh user@example.com "ls -la /home/domains/example.com/current/"
```

## Security Considerations

- Never commit sensitive data or `.env` files to git
- Add `.env*` to `.gitignore` (except `.env.example`)
- Use environment-specific files (`.env.production`, `.env.staging`)
- Store environment files in `shared/` directory on server (persists across deploys)
- Set restrictive permissions on environment files: `chmod 600 .env.*`
- Restrict SSH access to deployment user only
- Use SSH key authentication, never passwords
- Use firewall to limit access to deployment ports
- Regularly update server packages and security patches
- Monitor deployment logs for unusual activity
- Audit who has access to production environment files
- Rotate secrets periodically (database passwords, API keys, session secrets)

## Credits

**Portano Deployment Script**

Developed by **Gudasoft**
https://gudasoft.com

© 2026 Gudasoft. All rights reserved.
