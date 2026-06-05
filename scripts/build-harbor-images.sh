#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="${SHADOWBROKER_IMAGE_REPOSITORY:-harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker}"
TAG="${SHADOWBROKER_IMAGE_TAG:-}"
PUSH=false
PRINT_ONLY=false

usage() {
    cat <<'EOF'
Usage: ./scripts/build-harbor-images.sh [options]

Options:
  --repository <repo>  Image repository. Defaults to harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker
  --tag <tag>          Image tag suffix. Defaults to shortsha-yyyyMMdd-HHmmss
  --push               Push images after build
  --print-only         Print generated image names without building
  -h, --help           Show this help
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repository)
            REPOSITORY="${2:?--repository requires a value}"
            shift 2
            ;;
        --repository=*)
            REPOSITORY="${1#*=}"
            shift
            ;;
        --tag)
            TAG="${2:?--tag requires a value}"
            shift 2
            ;;
        --tag=*)
            TAG="${1#*=}"
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --print-only)
            PRINT_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$TAG" ]; then
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        SHORT_SHA="$(git rev-parse --short HEAD)"
    else
        SHORT_SHA="${CI_COMMIT_SHORT_SHA:-${SHADOWBROKER_GIT_SHORT_SHA:-}}"
    fi

    if [ -z "$SHORT_SHA" ]; then
        echo "ERROR: Could not determine short git SHA. Install git, run inside a git checkout, or set SHADOWBROKER_GIT_SHORT_SHA/CI_COMMIT_SHORT_SHA." >&2
        exit 1
    fi

    TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    TAG="${SHORT_SHA}-${TIMESTAMP}"
fi

export SHADOWBROKER_IMAGE_REPOSITORY="$REPOSITORY"
export SHADOWBROKER_IMAGE_TAG="$TAG"

cat > .env.harbor <<EOF
SHADOWBROKER_IMAGE_REPOSITORY=$REPOSITORY
SHADOWBROKER_IMAGE_TAG=$TAG
EOF

BACKEND_IMAGE="${REPOSITORY}:backend-${TAG}"
FRONTEND_IMAGE="${REPOSITORY}:frontend-${TAG}"

echo "SHADOWBROKER_IMAGE_TAG=$TAG"
echo "Wrote .env.harbor"
echo "Backend image:  $BACKEND_IMAGE"
echo "Frontend image: $FRONTEND_IMAGE"

if [ "$PRINT_ONLY" = true ]; then
    exit 0
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
else
    echo "ERROR: Could not find docker compose or docker-compose." >&2
    exit 1
fi

"${COMPOSE_CMD[@]}" -f docker-compose.yml -f docker-compose.harbor.yml build

if [ "$PUSH" = true ]; then
    "${COMPOSE_CMD[@]}" -f docker-compose.yml -f docker-compose.harbor.yml push
fi
