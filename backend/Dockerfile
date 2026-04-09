# WoundOS V2 Backend — GPU Worker Image
# CUDA 12.2 + COLMAP + Python 3.11 + ML Models (Depth Pro, SAM 2)

FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# System dependencies + Python 3.11 from deadsnakes PPA + COLMAP from apt
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3.11-dev python3.11-distutils \
    git cmake build-essential \
    libgl1-mesa-glx libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    colmap \
    wget curl \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default and install pip
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# Install Python dependencies
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY requirements-gpu.txt .
RUN pip install --no-cache-dir --break-system-packages --ignore-installed -r requirements-gpu.txt

# Install SAM 2 from GitHub (official Meta repo)
# MUST use editable install (-e) for Hydra config discovery to work.
# Non-editable pip install breaks Hydra's pkg://sam2 config path.
# See: https://github.com/facebookresearch/sam2/issues/26
RUN git clone https://github.com/facebookresearch/sam2.git /tmp/sam2 && \
    cd /tmp/sam2 && \
    pip install --break-system-packages -e . && \
    cd /app

# Install Depth Pro from GitHub (official Apple repo)
RUN pip install --no-cache-dir --break-system-packages git+https://github.com/apple/ml-depth-pro.git

# Download and cache ML models at build time
RUN mkdir -p /models/depth_pro /models/sam2

# Download SAM 2 checkpoint (~900 MB)
RUN wget -q --show-progress \
    -O /models/sam2/sam2.1_hiera_large.pt \
    "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt"

# Download Depth Pro weights (try at build time, fallback to runtime)
COPY scripts/download_models.py /tmp/download_models.py
RUN python3 /tmp/download_models.py || echo "Depth Pro will download at runtime" && rm -f /tmp/download_models.py

# Copy application code
COPY . .

# Default entrypoint: run both API and worker in one process
ENV WOUNDOS_WORKER_MODE=all
ENV WOUNDOS_HOST=0.0.0.0
ENV WOUNDOS_PORT=8080

EXPOSE 8080

CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
