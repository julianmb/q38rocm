#!/usr/bin/env bash
# ==============================================================================
# make-release.sh — Package the engine, publish the GitHub release, sync refs
# ==============================================================================
# Replaces the four hand-edits (build_engine.sh URL/SHA/version-expectation,
# Dockerfile ENGINE_RELEASE + ENGINE_TARBALL_SHA) that previously drifted —
# issue #20 and the v1.5.3 CI failure were both caused by manual bumps.
#
# Usage:
#   ./scripts/make-release.sh v1.6.0 [--notes-file FILE] [--skip-build]
#
# Requires: built binaries in engine/bin, gh auth, clean git tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${SCRIPT_DIR}"

VERSION="${1:-}"
NOTES_FILE=""
SKIP_BUILD=0
shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --notes-file) NOTES_FILE="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [ -z "${VERSION}" ] || [[ ! "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 vX.Y.Z [--notes-file FILE] [--skip-build]" >&2
    exit 2
fi

# 0. Preconditions
if git status --porcelain | grep -qv '^??'; then
    echo "❌ Git tree has uncommitted changes — commit or stash first." >&2
    exit 1
fi
for bin in llama-server llama-cli llama-bench llama-quantize; do
    if [ ! -x "engine/bin/${bin}" ]; then
        echo "❌ engine/bin/${bin} missing — run ./build_engine.sh (or drop --skip-build logic) first." >&2
        exit 1
    fi
done

# 1. Build from the pinned commit unless the caller already did
if [ "${SKIP_BUILD}" -eq 0 ]; then
    echo "[1/6] Building engine from pinned commit..."
    ./build_engine.sh > /tmp/make-release-build.log 2>&1 || {
        echo "❌ Build failed — see /tmp/make-release-build.log" >&2
        exit 1
    }
else
    echo "[1/6] Skipping build (--skip-build)"
fi

# 2. Verify provenance: the binary must report the pinned commit
EXPECTED_BUILD="$(grep -oE '[0-9a-f]{40}' build_engine.sh | head -1 | cut -c1-7)"
REPORTED="$(./engine/bin/llama-server --version 2>&1 | head -1)"
echo "[2/6] Provenance: ${REPORTED}"
if [[ "${REPORTED}" != *"${EXPECTED_BUILD}"* ]]; then
    echo "❌ Binary reports '${REPORTED}' but pinned commit is ${EXPECTED_BUILD}." >&2
    echo "   Refusing to release a binary that cannot be mapped to source." >&2
    exit 1
fi

# 3. Package + hash
echo "[3/6] Packaging ${VERSION}..."
STAGE="$(mktemp -d)/strix-halo-rocmfpx-engine"
mkdir -p "${STAGE}/bin"
cp engine/bin/llama-server engine/bin/llama-cli engine/bin/llama-bench engine/bin/llama-quantize "${STAGE}/bin/"
TARBALL="/tmp/strix-halo-rocmfpx-engine-${VERSION}-linux-x86_64.tar.gz"
tar -czf "${TARBALL}" -C "$(dirname "${STAGE}")" strix-halo-rocmfpx-engine
SHA="$(sha256sum "${TARBALL}" | cut -d' ' -f1)"
echo "      SHA256: ${SHA}"

# 4. Bump the four sync points
echo "[4/6] Bumping build_engine.sh + Dockerfile..."
sed -i "s|download/v[^/]*/strix-halo-rocmfpx-engine-v[^/]*-linux-x86_64.tar.gz|download/${VERSION}/strix-halo-rocmfpx-engine-${VERSION}-linux-x86_64.tar.gz|" build_engine.sh Dockerfile
sed -i "s|^EXPECTED_TARBALL_SHA=.*|EXPECTED_TARBALL_SHA=\"${SHA}\"|" build_engine.sh
sed -i "s|^ARG ENGINE_TARBALL_SHA=.*|ARG ENGINE_TARBALL_SHA=${SHA}|" Dockerfile
sed -i "s|^ARG ENGINE_RELEASE=.*|ARG ENGINE_RELEASE=${VERSION}|" Dockerfile
sed -i "s|PREBUILT_ENGINE_BUILD=\"\${PREBUILT_ENGINE_BUILD:-[^\"]*}\"|PREBUILT_ENGINE_BUILD=\"\${PREBUILT_ENGINE_BUILD:-${REPORTED}}\"|" build_engine.sh
sed -i "s|ROCmFPX Engine (v[^)]*)|ROCmFPX Engine (${VERSION})|; s|strix-halo-engine-[^\"']*\.tar\.gz|strix-halo-engine-${VERSION}.tar.gz|" build_engine.sh

# 5. Consistency gates — the same tests that caught manual-bump drift
echo "[5/6] Running consistency tests..."
bash tests/test_build_engine_flags.sh
bash -n build_engine.sh

# 6. Commit, release, upload
echo "[6/6] Committing, tagging, uploading..."
git add build_engine.sh Dockerfile
git commit -m "release: engine ${VERSION} — pinned-commit build, synced asset refs"
git push origin main
if [ -n "${NOTES_FILE}" ]; then
    gh release create "${VERSION}" --title "Engine ${VERSION} — pinned-commit build" --notes-file "${NOTES_FILE}"
else
    gh release create "${VERSION}" --title "Engine ${VERSION} — pinned-commit build" \
        --notes "Pre-built Strix Halo (gfx1151) static dual-backend engine from the pinned ROCmFPX commit. See engine/BUILD_INFO.txt for provenance. SHA256: \`${SHA}\`"
fi
gh release upload "${VERSION}" "${TARBALL}" --clobber

echo "================================================================================"
echo " ✅ ${VERSION} released. The release-triggered Docker build is running —"
echo "    verify the digest check with:"
echo "      curl -sL -o /tmp/v.tar.gz ${RELEASE_TARBALL_URL:-https://github.com/julianmb/q38rocm/releases/download/${VERSION}/strix-halo-rocmfpx-engine-${VERSION}-linux-x86_64.tar.gz}"
echo "      echo \"${SHA}  /tmp/v.tar.gz\" | sha256sum -c -"
echo "================================================================================"
