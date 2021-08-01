#!/bin/sh

export KUBECONFIG=$(pwd)/kubeconfig
touch $KUBECONFIG

export MINIKUBE_IN_STYLE=true

# Start minikube
minikube start --memory=10240M --cpus=2 --disk-size=20gb

# wait for kubernetes master start
minikube addons enable default-storageclass
minikube addons enable storage-provisioner
# minikube addons enable ingress

# create CRDs
echo "=== Create SolrCloud CRDs"
kubectl create -f manifests/all-with-dependencies.yaml

kubectl create namespace solr-operator

# create manifests/solr-operator.yml
if [ ! -f manifests/solr-operator.yml ]; then
  # this can be skiiped
  helm template solr-operator apache-solr/solr-operator  --version 0.3.0 --namespace solr-operator > manifests/solr-operator.yml
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

