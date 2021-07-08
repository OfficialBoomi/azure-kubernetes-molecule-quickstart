#!/bin/bash

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case "$key" in
    --resource_group|-rg)
      resource_group="$1"
      shift
      ;;
    --node_resource_group|-nrg)
      node_resource_group="$1"
      shift
      ;;
    --aks_name|-an)
      aks_name="$1"
      shift
      ;;
    --boomi_auth)
      boomi_auth="$1"
      shift
      ;;
    --boomi_token)
      boomi_token="$1"
      shift
      ;;
    --boomi_username)
      boomi_username="$1"
      shift
      ;;
    --boomi_password)
      boomi_password="$1"
      shift
      ;;
    --boomi_account)
      boomi_account="$1"
      shift
      ;;
    --fileshare)
      fileshare="$1"
      shift
      ;;
    --netAppIP)
      netAppIP="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
done

exec &> /var/log/bastion.log
set -x

#cfn signaling functions
yum install git -y || apt-get install -y git || zypper -n install git

#install kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --client

rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat <<EOF > /etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

yum install azure-cli -y

yum install -y nfs-utils

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

#Sign in with a managed identity
az login --identity

az aks get-credentials --resource-group "$resource_group" --name "$aks_name"

mkdir ~/$fileshare

mount -t nfs -o rw,hard,rsize=1048576,wsize=1048576,vers=4.1,tcp $netAppIP:/$fileshare ~/$fileshare

chmod -R 777 ~/$fileshare

if [ $boomi_auth == "token" ]
then
cat >/tmp/secrets.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: boomi-secret
type: Opaque
stringData:
  token: $boomi_token
  account: $boomi_account
EOF
else
cat >/tmp/secrets.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: boomi-secret
type: Opaque
stringData:
  username: $boomi_username
  password: $boomi_password
  account: $boomi_account
EOF
fi

cat >/tmp/persistentvolume.yaml <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: molecule-storage
spec:
  storageClassName: ""
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  mountOptions:
    - nfsvers=4.1
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: $netAppIP
    path: /$fileshare
EOF

cat >/tmp/persistentvolumeclam.yaml <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: molecule-storage
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 100Gi
EOF

kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml --kubeconfig=/root/.kube/config

#helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
#helm repo update
#helm install aad-pod-identity aad-pod-identity/aad-pod-identity --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/namespace.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/secrets.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolume.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolumeclam.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

if [ $boomi_auth == "token" ]
then
kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/statefulset_token.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
else
kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/statefulset_password.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
fi

kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/services.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/hpa.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

#helm repo add kedacore https://kedacore.github.io/charts
#helm repo update
#kubectl create namespace keda --kubeconfig=/root/.kube/config
#helm install keda kedacore/keda --namespace keda --kubeconfig=/root/.kube/config

#sleep 45

#kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/keda-hpa.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/quickstart-aks-boomi-molecule/main/kubernetes/ingress.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

rm /tmp/secrets.yaml

#sleep 600

#az network application-gateway probe update --name pb-aks-boomi-molecule-molecule-service-9090-molecule-ingress --path '/_admin/status' --gateway-name applicationgateway --resource-group "$node_resource_group"
