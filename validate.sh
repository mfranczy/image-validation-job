#!/bin/bash

set -e

image=$1
nodes=$2
namespace="image-validation"

validate_inputs() {
  if [ -z "$image" ]; then
    echo "Image argument is required!" >&2
    exit 1
  fi

  if [ -z "$nodes" ]; then
    nodes=$(kubectl get nodes -o custom-columns=":metadata.name")
  fi
}

generate_job_name() {
  local image=$1
  local counter=$2
  echo "$image-$counter" | sed -e 's/\//-/g; s/:/-/g; s/\./-/g'
}

ensure_namespace() {
  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "Namespace '$namespace' does not exist. Creating it..."
    kubectl create -f namespace.yaml
  else
    echo "Namespace '$namespace' already exists."
  fi
}

create_and_run_jobs() {
  echo "Deploying image validation jobs..."

  local counter=1
  for node in $nodes; do
    local job_name=$(generate_job_name "$image" "$counter")

    # Delete existing job (ignore errors)
    kubectl delete -nimage-validation --wait=true job "$job_name" >/dev/null 2>&1 || true

    # Create new job
    sed -e "s@{{IMAGE}}@$image@g; s@{{NODE_NAME}}@$node@g; s@{{JOB_NAME}}@$job_name@g" \
      "./image-validation-job.template" | kubectl create -f - >/dev/null 2>&1

    ((counter++))
  done

  # Wait for jobs to complete
  kubectl wait --for=condition=complete --timeout=300s -n image-validation -l image-validation-job=true job
}

fetch_logs() {
  local counter=1
  for node in $nodes; do
    local job_name=$(generate_job_name "$image" "$counter")

    echo "Node: $node"
    kubectl -nimage-validation logs -l batch.kubernetes.io/job-name=$job_name --tail=-1 || echo "Failed to fetch logs for $job_name"
    echo

    ((counter++))
  done
}

# Main script execution
validate_inputs
ensure_namespace
create_and_run_jobs
fetch_logs
