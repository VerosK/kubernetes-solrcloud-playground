#!/bin/sh

export KUBECONFIG=$(pwd)/kubeconfig
touch $KUBECONFIG

set -e
set -x

export MINIKUBE_IN_STYLE=true

# Start minikube

# wait for kubernetes master start
minikube addons enable default-storageclass
minikube addons enable storage-provisioner
# minikube addons enable ingress

# create CRDs
echo "=== Create SolrCloud CRDs"
kubectl create -f https://solr.apache.org/operator/downloads/crds/v0.7.0/all-with-dependencies.yaml

helm repo add apache-solr https://solr.apache.org/charts
helm repo update apache-solr


# create manifests/solr-operator.yml
if [ ! -f manifests/solr-operator.yml ]; then
  # this can be skiiped
  helm template solr-operator apache-solr/solr-operator  --version 0.7.0 --namespace solr-operator > manifests/solr-operator.yml
fi

# deploy solr operator
echo "=== Deploy solr operator"
kubectl apply -f manifests/solr-operator.yml -n solr-operator

# wait for operator to start up
echo "== Waiting for operator to start"
kubectl wait --for=condition=Available deployment/solr-operator -n solr-operator --timeout=120s

echo "== Starting new SolrCloud"
kubectl apply -f manifests/solr-cloud-test.yml -n default

sleep 30

for i in 0 1 2; do
  echo "=== Waiting for zookeeper ${i} to start"
  kubectl wait --for=condition=ready pod/test-solrcloud-zookeeper-${i} --timeout=300s
  echo "OK"
done

for i in 0 1 2; do
  echo "Waiting for solr ${i} to start"
  kubectl wait --for=condition=ready pod/test-solrcloud-${i} --timeout=300s
  echo "OK"
done

# Run port forward
echo Starting port forward from solr to http://localhost:8983/
kubectl port-forward svc/test-solrcloud-common 8983:8983

