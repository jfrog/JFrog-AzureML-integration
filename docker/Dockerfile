# Dockerfile for AzureML training with Artifactory integration
# Uses Python 3.11+ and installs packages from Artifactory PyPI repository during build
##TODO: change it to multi layer build
# Artifactory Docker registry and repository (optional - for backward compatibility)
# If provided, BASE_IMAGE will be constructed as: ${ARTIFACTORY_DOCKER_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/python:3.11-slim
# Otherwise defaults to public python:3.11-slim
ARG ARTIFACTORY_DOCKER_REGISTRY
ARG ARTIFACTORY_DOCKER_REPO
# Base image: defaults to python:3.11-slim, can be overridden with full path
# Example: docker build --build-arg BASE_IMAGE=your-registry.com/your-repo/python:3.11-slim
#ARG BASE_IMAGE=python:3.13.11-slim
ARG BASE_IMAGE=python:3.13.11-alpine
FROM ${BASE_IMAGE} AS builder

# Install build dependencies needed for compiling Python packages (e.g., scikit-learn)
# Note: Alpine uses apk package manager and musl libc (not glibc)
RUN apk add --no-cache \
        build-base \
        gcc \
        g++ \
        python3-dev \
        musl-dev \
        linux-headers

# Set working directory
WORKDIR /app

COPY requirements.txt /app/

# Install all Python dependencies from Artifactory (or PyPI if credentials not provided)
RUN --mount=type=secret,id=pipconfig,target=/etc/pip.conf \
    pip install --no-cache-dir -r /app/requirements.txt

# Verify pydash version to ensure CVE-2023-26145 is fixed (requires >= 6.0.0)
RUN echo "Verifying pydash version (CVE-2023-26145 fix check)..." && \
    pip show pydash && \
    python -c "import pydash; version = pydash.__version__; print(f'\n✓ Installed pydash version: {version}'); from packaging import version as pkg_version; assert pkg_version.parse(version) >= pkg_version.parse('6.0.0'), f'ERROR: pydash {version} is vulnerable (CVE-2023-26145). Requires >= 6.0.0'; print('✓ pydash version is secure (>= 6.0.0) - CVE-2023-26145 fixed\n')" || \
    (echo "\n❌ ERROR: pydash version check failed. Build aborted to prevent CVE-2023-26145 vulnerability." && exit 1)



FROM ${BASE_IMAGE} AS final

# NOTE: Alpine Linux uses musl libc, NOT glibc.
# If you need glibc 2.42-8, you must use a Debian-based image (e.g., python:3.13-slim)
# and install glibc from Debian unstable repository (see commented section below).

# Optional: Install glibc 2.42-8 (requires Debian-based image, not Alpine)
# Uncomment the following section if using a Debian-based image and you need glibc 2.42-8:
# RUN apt-get update && \
#     apt-get install -y --no-install-recommends ca-certificates gnupg && \
#     echo "deb http://deb.debian.org/debian unstable main" > /etc/apt/sources.list.d/unstable.list && \
#     printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n\n' > /etc/apt/preferences.d/unstable && \
#     printf 'Package: libc6 libc6-dbg libc-dev-bin libc6-dev libc-bin libc-l10n libc-gconv-modules-extra\n' \
#            'Pin: release a=unstable\nPin-Priority: 900\n' >> /etc/apt/preferences.d/unstable && \
#     apt-get update && \
#     apt-get install -y --no-install-recommends \
#       libc6=2.42-8 \
#       libc-bin=2.42-8 \
#       libc-l10n=2.42-8 && \
#     ldd --version | head -n1 && \
#     rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Remove pip and related tools to reduce attack surface
RUN rm -f /usr/local/bin/pip /usr/local/bin/pip3 /usr/local/bin/pip3.13 && \
    rm -rf /usr/local/lib/python3.13/site-packages/pip* && \
    rm -rf /usr/local/lib/python3.13/site-packages/pkg_resources* && \
    rm -rf /usr/local/lib/python3.13/site-packages/setuptools* && \
    rm -rf /usr/local/lib/python3.13/site-packages/wheel* || true

# Copy application code 
COPY src/ /app/src/    
# Set environment variables
ENV PYTHONPATH=/app

# Create entrypoint script (Alpine uses sh, not bash)
RUN echo '#!/bin/sh\n\
set -e\n\
echo "Executing command: $@"\n\
exec "$@"' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

# Default command: run training script (can be overridden by AzureML)
CMD ["python", "/app/src/train.py"]


