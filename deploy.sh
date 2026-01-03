#!/bin/bash

# Portano Deployment Script
# Developed by Gudasoft - https://gudasoft.com
#
# This script deploys the application and keeps the current and last 10 releases
# Shared directories (content, uploads, database, etc.) are symlinked to each release
# Environment-specific .env files are managed automatically
#
# Usage:
#   ./deploy.sh         # Show usage and folder structure
#   ./deploy.sh init    # Initialize remote directory structure (first-time)
#   ./deploy.sh build   # Build only
#   ./deploy.sh deploy  # Deploy only (assumes build/ exists)
#   ./deploy.sh all     # Build and deploy

set -e  # Exit on error

# Parse command line arguments
ACTION=${1:-""}

# Configuration
REMOTE_USER="user"
REMOTE_HOST="example.com"
DEPLOY_PATH="/home/domains/example.com"
RELEASES_PATH="${DEPLOY_PATH}/releases"
CURRENT_LINK="${DEPLOY_PATH}/current"
SHARED_PATH="${DEPLOY_PATH}/shared"
CURRENT_ENVIRONMENT="${NODE_ENV:-production}"
# Shared directories to symlink to each release
SHARED_SYMLINKS=(
  "content"
  "uploads"
)
MAX_RELEASES=10

# Generate release timestamp
RELEASE_NAME=$(date +%Y%m%d%H%M%S)
RELEASE_PATH="${RELEASES_PATH}/${RELEASE_NAME}"

# Functions

show_folder_structure() {
    echo ""
    echo "Remote Folder Structure:"
    echo ""
    echo "${DEPLOY_PATH}/"
    echo "├── current -> releases/YYYYMMDDHHMMSS/    # Symlink to active release"
    echo "├── releases/"
    echo "│   ├── 20260103143022/                    # Current release"
    echo "│   │   ├── index.js"
    echo "│   │   ├── package.json"
    echo "│   │   ├── .env -> ../../shared/.env.${CURRENT_ENVIRONMENT}"
    for item in "${SHARED_SYMLINKS[@]}"; do
        echo "│   │   ├── ${item} -> ../../shared/${item}"
    done
    echo "│   ├── 20260103120815/                    # Previous release"
    echo "│   └── 20260103101234/                    # Older release"
    echo "└── shared/"
    echo "    ├── .env.${CURRENT_ENVIRONMENT}                    # Environment config"
    for item in "${SHARED_SYMLINKS[@]}"; do
        if [[ "${item}" =~ \. ]]; then
            # Item has extension, likely a file
            echo "    ├── ${item}                              # File"
        else
            # Item is a directory
            echo "    ├── ${item}/"
        fi
    done
}

show_usage() {
    echo "Portano Deployment Script"
    echo "Developed by Gudasoft - https://gudasoft.com"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  init    - Initialize remote directory structure (first-time setup)"
    echo "  build   - Build the application locally only"
    echo "  deploy  - Deploy existing build to server (skips build step)"
    echo "  all     - Build and deploy"
    echo ""
    echo "Examples:"
    echo "  $0 init     # Initialize remote server structure"
    echo "  $0 all      # Build and deploy"
    echo "  $0 build    # Build only"
    echo "  $0 deploy   # Deploy only"

    show_folder_structure
    exit 1
}

log_info() {
    echo "==> $1"
}

log_success() {
    echo "==> ✓ $1"
}

log_error() {
    echo "==> ✗ Error: $1" >&2
}

init_remote_structure() {
    log_info "Initializing remote directory structure..."
    log_info "Target: ${REMOTE_HOST}:${DEPLOY_PATH}"
    echo ""

    ssh ${REMOTE_USER}@${REMOTE_HOST} "
      mkdir -p ${RELEASES_PATH}
      mkdir -p ${SHARED_PATH}
      for item in ${SHARED_SYMLINKS[@]}; do
        # Only create as directory if item doesn't have a file extension
        if [[ ! \"\${item}\" =~ \\.  ]]; then
          mkdir -p ${SHARED_PATH}/\${item}
        fi
      done
    "

    log_success "Directory structure initialized"
    echo ""
    echo "Created directories:"
    echo "  - ${DEPLOY_PATH}/releases"
    echo "  - ${DEPLOY_PATH}/shared"
    for item in "${SHARED_SYMLINKS[@]}"; do
        # Only list directories (items without file extensions)
        if [[ ! "${item}" =~ \. ]]; then
            echo "  - ${DEPLOY_PATH}/shared/${item}/"
        fi
    done
    echo ""
    echo "Note: Files (like database.db) will be created during first deployment"
    echo ""
    log_info "Server is ready for deployments"
}

build_application() {
    log_info "Building application..."
    npm install
    npm run build
    log_success "Build complete"
}

create_remote_directories() {
    log_info "Creating directory structure on remote server..."
    ssh ${REMOTE_USER}@${REMOTE_HOST} "
      mkdir -p ${RELEASES_PATH}
      for item in ${SHARED_SYMLINKS[@]}; do
        mkdir -p ${SHARED_PATH}/\${item}
      done
    "
    log_success "Directory structure created"
}

upload_application_files() {
    log_info "Uploading application files to ${RELEASE_PATH}..."
    rsync -avz \
      --exclude='.git' \
      --exclude='node_modules' \
      --exclude='.svelte-kit' \
      --exclude='.claude' \
      --exclude='content' \
      build/ ${REMOTE_USER}@${REMOTE_HOST}:${RELEASE_PATH}/
    log_success "Application files uploaded"
}

upload_static_files() {
    log_info "Uploading static files (overwriting duplicates)..."
    rsync -avz \
      static/ ${REMOTE_USER}@${REMOTE_HOST}:${RELEASE_PATH}/
    log_success "Static files uploaded"
}

sync_shared_directories() {
    log_info "Syncing shared directories..."
    for item in "${SHARED_SYMLINKS[@]}"; do
        if [[ -e "${item}" ]]; then
            rsync -avz "${item}/" ${REMOTE_USER}@${REMOTE_HOST}:${SHARED_PATH}/${item}/
            log_success "Synced ${item}"
        else
            log_info "Skipping ${item} (not found locally)"
        fi
    done
}

create_shared_symlinks() {
    log_info "Creating symlinks for shared directories..."
    for item in "${SHARED_SYMLINKS[@]}"; do
        ssh ${REMOTE_USER}@${REMOTE_HOST} "ln -sfn ${SHARED_PATH}/${item} ${RELEASE_PATH}/${item}"
        log_success "Symlinked ${item}"
    done
}

sync_environment_file() {
    local ENV_FILE=".env.${CURRENT_ENVIRONMENT}"
    local SHARED_ENV_FILE="${SHARED_PATH}/${ENV_FILE}"

    log_info "Managing environment file for: ${CURRENT_ENVIRONMENT}"

    # Sync local .env file to shared folder if it exists locally
    if [[ -f "${ENV_FILE}" ]]; then
        log_info "Syncing ${ENV_FILE} to shared folder..."
        rsync -avz "${ENV_FILE}" ${REMOTE_USER}@${REMOTE_HOST}:${SHARED_ENV_FILE}
        log_success "Environment file synced"
    else
        log_info "No local ${ENV_FILE} found, skipping sync"
    fi

    # Create symlink from shared env file to release .env if it exists on server
    log_info "Creating environment file symlink..."
    ssh ${REMOTE_USER}@${REMOTE_HOST} "
      if [[ -f ${SHARED_ENV_FILE} ]]; then
        ln -sfn ${SHARED_ENV_FILE} ${RELEASE_PATH}/.env
        echo 'Symlinked ${SHARED_ENV_FILE} -> ${RELEASE_PATH}/.env'
      else
        echo 'No ${ENV_FILE} found in shared folder, skipping symlink'
      fi
    "
}

update_current_symlink() {
    log_info "Updating current release symlink..."
    ssh ${REMOTE_USER}@${REMOTE_HOST} "ln -sfn ${RELEASE_PATH} ${CURRENT_LINK}"
    log_success "Current symlink updated to ${RELEASE_NAME}"
}

cleanup_old_releases() {
    log_info "Cleaning up old releases (keeping last ${MAX_RELEASES})..."
    ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${RELEASES_PATH} && ls -1dt */ | tail -n +$((MAX_RELEASES + 1)) | xargs -r rm -rf"

    RELEASE_COUNT=$(ssh ${REMOTE_USER}@${REMOTE_HOST} "ls -1d ${RELEASES_PATH}/*/ 2>/dev/null | wc -l" || echo "0")
    log_success "Old releases cleaned up (${RELEASE_COUNT} releases kept)"
}

print_deployment_summary() {
    echo ""
    echo "========================================="
    echo "Deployment Summary"
    echo "========================================="
    echo "Release:       ${RELEASE_NAME}"
    echo "Environment:   ${CURRENT_ENVIRONMENT}"
    echo "Remote host:   ${REMOTE_HOST}"
    echo "Deploy path:   ${DEPLOY_PATH}"
    echo "Shared paths:  ${SHARED_SYMLINKS[*]}"
    echo "========================================="
    log_success "Deployment complete!"
}

# Main deployment flow

main() {
    # Show usage if no command provided
    if [[ -z "$ACTION" ]]; then
        show_usage
    fi

    # Validate action
    case "$ACTION" in
        init|build|deploy|all)
            ;;
        *)
            log_error "Invalid command: $ACTION"
            show_usage
            ;;
    esac

    # Init step
    if [[ "$ACTION" == "init" ]]; then
        init_remote_structure
        exit 0
    fi

    # Build step
    if [[ "$ACTION" == "build" || "$ACTION" == "all" ]]; then
        log_info "Running build step..."
        echo ""
        build_application
        echo ""
        log_success "Build completed successfully!"

        if [[ "$ACTION" == "build" ]]; then
            echo ""
            echo "Build artifacts are in the 'build/' directory"
            echo "Run './deploy.sh deploy' to deploy to server"
            exit 0
        fi
    fi

    # Deploy step
    if [[ "$ACTION" == "deploy" || "$ACTION" == "all" ]]; then
        # Verify build exists
        if [[ ! -d "build" ]]; then
            log_error "Build directory not found. Run './deploy.sh build' first"
            exit 1
        fi

        log_info "Starting deployment to ${REMOTE_HOST}"
        log_info "Release: ${RELEASE_NAME}"
        echo ""

        create_remote_directories
        upload_application_files
        upload_static_files
        sync_shared_directories
        create_shared_symlinks
        sync_environment_file
        update_current_symlink
        cleanup_old_releases
        print_deployment_summary
    fi
}

# Run main deployment
main
