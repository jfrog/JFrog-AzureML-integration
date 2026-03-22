# (c) JFrog Ltd (2026).
# Dockerfile for AzureML training with Artifactory integration
# Uses Python 3.11+ and installs packages from Artifactory PyPI repository during build
# Artifactory Docker registry and repository (optional - for backward compatibility)
# If provided, BASE_IMAGE will be constructed as: ${ARTIFACTORY_DOCKER_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/python:3.11-slim
# Otherwise defaults to public python:3.11-slim
ARG ARTIFACTORY_DOCKER_REGISTRY
ARG ARTIFACTORY_DOCKER_REPO
# Base image: defaults to python:3.11-slim, can be overridden with full path
# Example: docker build --build-arg BASE_IMAGE=your-registry.com/your-repo/python:3.11-slim
ARG BASE_IMAGE=python:3.13.11-slim
FROM ${BASE_IMAGE} AS builder



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


