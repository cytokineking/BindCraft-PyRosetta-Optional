FROM nvidia/cuda:12.6-cudnn8-runtime-ubuntu22.04

LABEL org.opencontainers.image.source="https://github.com/cytokineking/FreeBindCraft"
LABEL org.opencontainers.image.description="FreeBindCraft GPU (no PyRosetta)"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

# OS dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      rsync \
      libgfortran5 \
      tmux \
      wget \
      build-essential \
      pkg-config \
      procps \
      unzip && \
    rm -rf /var/lib/apt/lists/*

## CUDA-only image

# Install Miniforge (Conda) at /miniforge3
ENV CONDA_DIR=/miniforge3
RUN wget -q https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && \
    rm -f /tmp/miniforge.sh

# Put conda on PATH
ENV PATH=${CONDA_DIR}/bin:${PATH}

# Improve conda robustness and cleanup
RUN conda config --set channel_priority strict && \
    conda config --set always_yes yes && \
    conda config --set subdir linux-64 && \
    conda update -n base -c conda-forge conda && \
    conda clean -afy

# Create workdir and copy project
WORKDIR /app
COPY . /app

# Ensure helper binaries are executable (also handled by installer)
RUN chmod +x /app/functions/dssp || true && \
    chmod +x /app/functions/sc || true

# Build environment and download AF2 weights without PyRosetta
# Match CUDA to base image; installer pins jax/jaxlib=0.6.0
# Allow toggling PyRosetta install at build-time
ARG WITH_PYROSETTA=false
ENV WITH_PYROSETTA=${WITH_PYROSETTA}
RUN bash -lc 'source ${CONDA_DIR}/etc/profile.d/conda.sh && \
    EXTRA=""; if [ "${WITH_PYROSETTA}" != "true" ]; then EXTRA="--no-pyrosetta"; fi; \
    bash /app/install_bindcraft.sh --pkg_manager conda --cuda 12.6 ${EXTRA}'

# Default environment
ENV PATH=${CONDA_DIR}/envs/BindCraft/bin:${CONDA_DIR}/bin:${PATH} \
    LD_LIBRARY_PATH=${CONDA_DIR}/envs/BindCraft/lib:${LD_LIBRARY_PATH} \
    PYTHONUNBUFFERED=1 \
    BINDCRAFT_HOME=/app

# Prefer CUDA in OpenMM by default (CUDA-only)
ENV OPENMM_PLATFORM_ORDER=CUDA \
    OPENMM_DEFAULT_PLATFORM=CUDA

# Modal-compatible entrypoint that execs args
COPY docker-entrypoint.sh /usr/local/bin/bindcraft-entrypoint.sh
RUN chmod +x /usr/local/bin/bindcraft-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/bindcraft-entrypoint.sh"]

# Default command prints help
CMD ["python", "bindcraft.py", "--help"]
