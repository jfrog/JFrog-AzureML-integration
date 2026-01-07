# Dockerfile for AzureML training with Artifactory integration
# Uses Python 3.11+ and installs packages from Artifactory PyPI repository during build
##TODO: change it to multi layer build
ARG ARTIFACTORY_DOCKER_REGISTRY
ARG ARTIFACTORY_DOCKER_REPO

FROM ${ARTIFACTORY_DOCKER_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/python:3.11-slim as builder


# Set working directory
WORKDIR /app

COPY requirements.txt /app/

# Install all Python dependencies from Artifactory (or PyPI if credentials not provided)
RUN --mount=type=secret,id=pipconfig,target=/etc/pip.conf \
    pip install --no-cache-dir -r /app/requirements.txt

FROM ${ARTIFACTORY_DOCKER_REGISTRY}/${ARTIFACTORY_DOCKER_REPO}/python:3.11-slim as final

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin


# Copy application code 
COPY src/ /app/src/    
# Set environment variables
ENV PYTHONPATH=/app

# Create entrypoint script (packages already installed, just execute command)
RUN echo '#!/bin/bash\n\
set -e\n\
echo "Executing command: $@"\n\
exec "$@"' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

# Default command: run training script (can be overridden by AzureML)
CMD ["python", "/app/src/train.py"]


