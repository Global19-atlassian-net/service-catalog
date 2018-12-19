#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail
set -o xtrace


for sig in INT TERM EXIT; do
    trap "set +e;oc delete subscription svcat -n kube-service-catalog; oc delete clusterserviceversion svcat.v0.1.34 -n kube-service-catalog; oc delete namespace kube-service-catalog; [[ $sig == EXIT ]] || kill -$sig $BASHPID" $sig
done


echo "`date`: Waiting for up to 10 minutes for Service Catalog APIs to be available..."

TARGET="$(date -d '5 minutes' +%s)"
NOW="$(date +%s)"
while [[ "${NOW}" -lt "${TARGET}" ]]; do
  REMAINING="$((TARGET - NOW))"
  if oc --request-timeout="${REMAINING}s" get --raw /apis/servicecatalog.k8s.io/v1beta1 ; then
    break
  fi
  sleep 20
  NOW="$(date +%s)"
done

if [ "${NOW}" -ge "${TARGET}" ];then
    echo "`date`: timeout waiting for service-catalog apis to be available"
    oc describe pods -n kube-service-catalog 2>&1 tee /tmp/artifacts/descript-catalog-pods.txt
    oc get events -n kube-service-catalog 2>&1 tee /tmp/artifacts/catalog-events.txt
    oc get all -n kube-service-catalog tee 2>&1 /tmp/artifacts/get-all-in-catalog-ns.txt
    oc get operatorgroups --all-namespaces tee 2>&1 /tmp/artifacts/all-operator-groups.txt
#    exit 1
fi

echo "Add missing rbac"
set +e
cat <<'EOF' | oc create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: add-servicebindingfinalizers
rules:
- apiGroups:
  - servicecatalog.k8s.io
  resources:
  - servicebindings/finalizers
  verbs:
  - update
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: add-servicebindingfinalizers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: add-servicebindingfinalizers
subjects:
- kind: ServiceAccount
  name: service-catalog-controller
  namespace: kube-service-catalog
EOF
sleep 20
set -e


echo "`date`: Service Catalog APIs available, executing Service Catalog E2E"

SERVICECATALOGCONFIG=$KUBECONFIG bin/e2e.test -v 10 -alsologtostderr -broker-image quay.io/kubernetes-service-catalog/user-broker:latest