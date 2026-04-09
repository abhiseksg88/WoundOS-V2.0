#!/usr/bin/env bash
# Deploy WoundOS V2 GPU Worker to GCE VM with NVIDIA L4
#
# This script:
# 1. Builds the GPU worker Docker image via Cloud Build
# 2. Creates a GCE VM with L4 GPU (if it doesn't exist)
# 3. SSHs into the VM and starts the worker container
#
# Prerequisites:
# - GCP project configured (gcloud config set project ...)
# - Artifact Registry repo exists (run setup_gcp.sh first)
# - ANTHROPIC_API_KEY environment variable set
#
# Usage:
#   export ANTHROPIC_API_KEY=sk-ant-xxx
#   bash scripts/deploy_gce_worker.sh

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-careplix-woundos}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/woundos"
WORKER_IMAGE="${REGISTRY}/worker:latest"
VM_NAME="woundos-gpu-worker"
MACHINE_TYPE="g2-standard-8"
GPU_TYPE="nvidia-l4"
BOOT_DISK_SIZE="200GB"

echo "============================================"
echo "  WoundOS V2 — GPU Worker Deployment"
echo "============================================"
echo "Project:  ${PROJECT_ID}"
echo "Region:   ${REGION}"
echo "Zone:     ${ZONE}"
echo "VM:       ${VM_NAME}"
echo "Machine:  ${MACHINE_TYPE} + ${GPU_TYPE}"
echo "Image:    ${WORKER_IMAGE}"
echo ""

# ─── Step 1: Build GPU Worker Image ──────────────────────────

echo "=== Step 1: Building GPU Worker Docker Image ==="
echo "This will take 15-25 minutes (COLMAP compilation + model downloads)..."
echo ""

gcloud builds submit \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --config=cloudbuild-worker.yaml \
    --substitutions="_IMAGE_TAG=${WORKER_IMAGE}" \
    .

echo ""
echo "✓ Worker image built and pushed to ${WORKER_IMAGE}"
echo ""

# ─── Step 2: Create GCE VM ───────────────────────────────────

echo "=== Step 2: Creating GCE VM with L4 GPU ==="

# Check if VM already exists
if gcloud compute instances describe "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
    echo "VM ${VM_NAME} already exists. Updating container..."

    # Stop existing container, pull new image, restart
    gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --command="
        sudo docker stop woundos-worker 2>/dev/null || true
        sudo docker rm woundos-worker 2>/dev/null || true
        sudo docker pull ${WORKER_IMAGE}
        sudo docker run -d --gpus all --restart=always \
            --name woundos-worker \
            -e WOUNDOS_WORKER_MODE=gpu \
            -e WOUNDOS_GCP_PROJECT_ID=${PROJECT_ID} \
            -e WOUNDOS_ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-} \
            ${WORKER_IMAGE} \
            python3 -m worker.main
    "
else
    echo "Creating new VM..."

    gcloud compute instances create "${VM_NAME}" \
        --project="${PROJECT_ID}" \
        --zone="${ZONE}" \
        --machine-type="${MACHINE_TYPE}" \
        --accelerator="count=1,type=${GPU_TYPE}" \
        --maintenance-policy=TERMINATE \
        --boot-disk-size="${BOOT_DISK_SIZE}" \
        --boot-disk-type=pd-ssd \
        --image-family=ubuntu-2204-lts \
        --image-project=ubuntu-os-cloud \
        --scopes=cloud-platform \
        --tags=woundos-worker

    echo ""
    echo "✓ VM created. Waiting 60s for boot..."
    sleep 60

    echo "=== Step 3: Installing NVIDIA Drivers + Docker ==="

    gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --command="
        set -e

        echo '>>> Installing NVIDIA drivers...'
        sudo apt-get update -qq
        sudo apt-get install -y -qq linux-headers-\$(uname -r)

        # Add NVIDIA driver repo
        sudo apt-get install -y -qq software-properties-common
        sudo add-apt-repository -y ppa:graphics-drivers/ppa
        sudo apt-get update -qq
        sudo apt-get install -y -qq nvidia-driver-535

        echo '>>> Installing Docker...'
        sudo apt-get install -y -qq docker.io

        echo '>>> Installing NVIDIA Container Toolkit...'
        distribution=\$(. /etc/os-release; echo \$ID\$VERSION_ID)
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        curl -s -L https://nvidia.github.io/libnvidia-container/\${distribution}/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
        sudo apt-get update -qq
        sudo apt-get install -y -qq nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker

        echo '>>> Configuring Artifact Registry auth...'
        gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

        echo '>>> Installation complete. Rebooting for NVIDIA drivers...'
    "

    echo "Rebooting VM for NVIDIA driver activation..."
    gcloud compute instances reset "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}"
    echo "Waiting 90s for reboot..."
    sleep 90

    echo "=== Step 4: Starting Worker Container ==="

    gcloud compute ssh "${VM_NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --command="
        set -e

        echo '>>> Verifying GPU...'
        nvidia-smi

        echo '>>> Pulling worker image...'
        sudo docker pull ${WORKER_IMAGE}

        echo '>>> Starting worker container...'
        sudo docker run -d --gpus all --restart=always \
            --name woundos-worker \
            -e WOUNDOS_WORKER_MODE=gpu \
            -e WOUNDOS_GCP_PROJECT_ID=${PROJECT_ID} \
            -e WOUNDOS_ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-} \
            ${WORKER_IMAGE} \
            python3 -m worker.main

        echo '>>> Worker started. Checking logs...'
        sleep 5
        sudo docker logs woundos-worker
    "
fi

echo ""
echo "============================================"
echo "  GPU Worker Deployment Complete"
echo "============================================"
echo ""
echo "VM:     ${VM_NAME} (${ZONE})"
echo "Image:  ${WORKER_IMAGE}"
echo ""
echo "Commands:"
echo "  View logs:    gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command='sudo docker logs -f woundos-worker'"
echo "  SSH into VM:  gcloud compute ssh ${VM_NAME} --zone=${ZONE}"
echo "  Stop worker:  gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command='sudo docker stop woundos-worker'"
echo "  Stop VM:      gcloud compute instances stop ${VM_NAME} --zone=${ZONE}"
echo "  Delete VM:    gcloud compute instances delete ${VM_NAME} --zone=${ZONE}"
echo ""
