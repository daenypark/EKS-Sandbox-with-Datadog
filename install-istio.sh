#!/bin/bash
# Installing with Helm
# https://istio.io/latest/docs/setup/install/helm/
# Alternatives
# https://istio.io/latest/docs/setup/install/

echo "**Adding Helm Repos**"
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

echo "**Setting up Istio**"
kubectl create namespace istio-system
helm install istio-base istio/base -n istio-system --set defaultRevision=default

echo "**Validating Istio Base**"
helm ls -n istio-system

helm install istiod istio/istiod -n istio-system
helm status istiod -n istio-system
kubectl get deployments -n istio-system --output wide

echo "**Creating [test-istio] namespace for injection**"
kubectl create namespace test-istio
kubectl label namespace test-istio istio-injection=enabled
