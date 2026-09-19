#!/usr/bin/env bash
set -e

# OrbisNav Google Cloud Run Deployment Script
# Deploys the universal vision server as a highly scalable public cloud microservice

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "your-gcp-project")
REGION="us-central1"
SERVICE_NAME="orbisnav-vision-api"
IMAGE_TAG="gcr.io/${PROJECT_ID}/${SERVICE_NAME}:latest"

echo "=========================================================="
echo " Deploying OrbisNav Vision Server to Google Cloud Run"
echo " Project: ${PROJECT_ID} | Region: ${REGION}"
echo "=========================================================="

# Build and push to Google Container Registry
echo "[1/3] Building container image with Google Cloud Build..."
gcloud builds submit --tag "${IMAGE_TAG}" .

# Deploy to Cloud Run
echo "[2/3] Deploying to Cloud Run service..."
gcloud run deploy "${SERVICE_NAME}" \
    --image "${IMAGE_TAG}" \
    --platform managed \
    --region "${REGION}" \
    --allow-unauthenticated \
    --memory 2Gi \
    --cpu 2 \
    --concurrency 40 \
    --timeout 60s \
    --port 8000

# Retrieve Public Endpoint URL
SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" --platform managed --region "${REGION}" --format 'value(status.url)')

echo "=========================================================="
echo " Deployment Complete!"
echo " Public Cloud Endpoint: ${SERVICE_URL}"
echo " Detect URL: ${SERVICE_URL}/detect"
echo "=========================================================="
