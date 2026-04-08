# WoundOS V2 Backend — GPU Worker Image
# CUDA 12.2 + COLMAP + Python 3.11 + ML Models (Depth Pro, SAM 2)

FROM nvidia/cuda:12.2.0-devel-ubuntu22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 python3.11-venv python3-pip python3.11-dev \
    git cmake build-essential \
    libgl1-mesa-glx libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libboost-all-dev libcgal-dev libeigen3-dev libflann-dev \
    libfreeimage-dev libgoogle-glog-dev libgtest-dev \
    libsqlite3-dev libglew-dev qtbase5-dev libqt5opengl5-dev \
    wget curl \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1

# Install COLMAP from source (for CUDA support)
RUN git clone https://github.com/colmap/colmap.git /tmp/colmap && \
    cd /tmp/colmap && \
    git checkout 3.9.1 && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CUDA_ARCHITECTURES="70;75;80;86;89;90" \
             -DCUDA_ENABLED=ON && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/colmap

# Upgrade pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install Python dependencies
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY requirements-gpu.txt .
RUN pip install --no-cache-dir -r requirements-gpu.txt

# Install Depth Pro from git
RUN pip install --no-cache-dir git+https://github.com/apple/ml-depth-pro.git

# Download and cache ML models at build time
RUN mkdir -p /models/depth_pro /models/sam2

# Download Depth Pro weights
COPY scripts/download_models.py /tmp/download_models.py
RUN python3 /tmp/download_models.py && rm /tmp/download_models.py

# Copy application code
COPY . .

# Default entrypoint: run both API and worker in one process
ENV WOUNDOS_WORKER_MODE=all
ENV WOUNDOS_HOST=0.0.0.0
ENV WOUNDOS_PORT=8080

EXPOSE 8080

CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
