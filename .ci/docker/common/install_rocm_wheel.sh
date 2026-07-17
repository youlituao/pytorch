#!/usr/bin/env bash
# Script used only in CD pipeline.
#
# Installs ROCm from the multi-arch TheRock wheel index instead of OS packages
# or tarballs. The ROCm SDK is pip-installed and its root is symlinked to
# /opt/rocm so the rest of the manywheel build (build_env_setup.py /
# repair_wheel.py) can keep discovering ROCm at the usual /opt/rocm location.

set -exou pipefail

# https://repo.amd.com/rocm/whl-multi-arch/ hosts the multi-arch ROCm wheels.
THEROCK_INDEX_URL="${THEROCK_INDEX_URL:-https://repo.amd.com/rocm/whl-multi-arch/}"
# Pin to the published rocm meta-package on the multi-arch index (currently 7.14.0).
THEROCK_VERSION="${THEROCK_VERSION:-7.14.0}"

echo "=============================================="
echo "ROCm Multi-Arch Wheel Installation (TheRock)"
echo "=============================================="
echo "Index URL:      ${THEROCK_INDEX_URL}"
echo "ROCm version:   ${THEROCK_VERSION}"
echo "=============================================="

# Remove any pre-existing /opt/rocm (file, dir or dangling symlink) so we can
# repoint it at the wheel-provided ROCm SDK.
if [[ -e /opt/rocm || -L /opt/rocm ]]; then
    rm -rf /opt/rocm
fi

# device-all pulls in the kernels for every supported gfx target so the built
# wheel is multi-arch; libraries+devel provide the runtime libs and the
# headers/hipcc needed to compile PyTorch against ROCm.
python3 -m pip install \
    --index-url "${THEROCK_INDEX_URL}" \
    "rocm[libraries,devel,device-all]==${THEROCK_VERSION}"

# Discover the install root/bin via the rocm-sdk CLI helper (shipped by the
# rocm-sdk-core wheel).
ROCM_HOME="$(rocm-sdk path --root)"
ROCM_BIN="$(rocm-sdk path --bin)"

echo "ROCM_HOME=${ROCM_HOME}"
echo "ROCM_BIN=${ROCM_BIN}"

# Point /opt/rocm at the wheel-provided ROCm SDK. This mirrors the old tarball
# install (/opt/rocm -> /opt/rocm-<version>) so downstream scripts that assume
# /opt/rocm keep working unchanged.
ln -sfn "${ROCM_HOME}" /opt/rocm

# theRock bundles system dependencies (libdrm, liblzma, etc.) under
# lib/rocm_sysdeps; expose them alongside the core ROCm libs.
ROCM_SYSDEPS_LIB="/opt/rocm/lib/rocm_sysdeps/lib"

cat > /etc/rocm_env.sh << 'ROCM_ENV'
# ROCm environment for the TheRock wheel install. /opt/rocm is a symlink to the
# pip-installed ROCm SDK root.
export ROCM_PATH=/opt/rocm
export ROCM_HOME=/opt/rocm
export PATH=/opt/rocm/bin:${PATH}
export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib/rocm_sysdeps/lib:${LD_LIBRARY_PATH:-}
ROCM_ENV

echo "source /etc/rocm_env.sh" >> /etc/bashrc || true

echo "=============================================="
echo "TheRock ROCm wheel install complete"
echo "ROCM_HOME=${ROCM_HOME} (symlinked to /opt/rocm)"
if [[ -d "${ROCM_SYSDEPS_LIB}" ]]; then
    echo "rocm_sysdeps libs: ${ROCM_SYSDEPS_LIB}"
fi
echo "=============================================="
