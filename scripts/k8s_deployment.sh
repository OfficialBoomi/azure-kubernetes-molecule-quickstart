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
    --molecule_cluster_name|-mcn)
      molecule_cluster_name="$1"
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
    --appgw_ssl_cert)
      appgw_ssl_cert="$1"
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

mount -t nfs -o rw,hard,rsize=1048576,wsize=1048576,vers=3,tcp $netAppIP:/$fileshare ~/$fileshare

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
    - vers=3
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

cat >/tmp/ingress.yaml <<EOF
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: molecule-ingress
  annotations:
    kubernetes.io/ingress.class: "azure/application-gateway"
    appgw.ingress.kubernetes.io/health-probe-path: "/_admin/status"
    #appgw.ingress.kubernetes.io/appgw-ssl-certificate: "$appgw_ssl_cert"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: molecule-service
            port:
              number: 9090
EOF

cat >/tmp/statefulset_password.yaml <<EOF
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: molecule
  labels:
    app: molecule
spec:
  selector:
    matchLabels:
      app: molecule
  serviceName: "molecule-service"
  replicas: 3
  template:
    metadata:
      labels:
        app: molecule
    spec:
      terminationGracePeriodSeconds: 60
      volumes:
        - name: molecule-storage
          persistentVolumeClaim:
            claimName: molecule-storage
        - name: tmpfs
          emptyDir: {}
        - name: cgroup
          hostPath:
            path: /sys/fs/cgroup
            type: Directory
      nodeSelector:
        agentpool: userpool
      containers:
      - image: jaygazulaboomi/v4:latest
        imagePullPolicy: Always
        name: atom-node
        ports:
        - name: http
          containerPort: 9090
          protocol: TCP
        - name: https
          containerPort: 9093
          protocol: TCP
        lifecycle:
          preStop:
            exec:
              command:
                - sh
                - /home/boomi/scaledown.sh
        resources:
          limits:
            cpu: "1000m"
            memory: "1536Mi"
          requests:
            cpu: "500m"
            memory: "1024Mi"
        volumeMounts:
          - mountPath: "/mnt/boomi"
            name: molecule-storage
          - name: tmpfs
            mountPath: "/run"
          - name: tmpfs
            mountPath: "/tmp"
          - name: cgroup
            mountPath: /sys/fs/cgroup
        startupProbe:
          timeoutSeconds: 90
          failureThreshold: 90
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - startup
        readinessProbe:
          timeoutSeconds: 60
          periodSeconds: 10
          initialDelaySeconds: 10
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - readiness
        livenessProbe:
          timeoutSeconds: 60
          periodSeconds: 60
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - liveness
        env:
        - name: BOOMI_ATOMNAME
          value: "Boomi-AKS"
        - name: ATOM_LOCALHOSTID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: BOOMI_ACCOUNTID
          valueFrom:
            secretKeyRef:
              name: boomi-secret
              key: account
        - name: BOOMI_USERNAME
          valueFrom:
            secretKeyRef:
              name: boomi-secret
              key: username
        - name: BOOMI_PASSWORD
          valueFrom:
            secretKeyRef:
              name: boomi-secret
              key: password
        - name: BOOMI_CONTAINERNAME
          value: "$molecule_cluster_name"
        - name: INSTALLATION_DIRECTORY
          value: "/mnt/boomi"
        - name: CONTAINER_PROPERTIES_OVERRIDES
          value: "com.boomi.deployment.quickstart=True|com.boomi.container.is.orchestrated.container=true|com.boomi.container.cloudlet.findInitialHostsTimeout=5000|com.boomi.container.elasticity.asyncPollerTimeout=75000|com.boomi.container.elasticity.forceRestartOverride=50000"
EOF

cat >/tmp/statefulset_token.yaml <<EOF
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: molecule
  labels:
    app: molecule
spec:
  selector:
    matchLabels:
      app: molecule
  serviceName: "molecule-service"
  replicas: 3
  template:
    metadata:
      labels:
        app: molecule
    spec:
      terminationGracePeriodSeconds: 60
      volumes:
        - name: molecule-storage
          persistentVolumeClaim:
            claimName: molecule-storage
        - name: tmpfs
          emptyDir: {}
        - name: cgroup
          hostPath:
            path: /sys/fs/cgroup
            type: Directory
      nodeSelector:
        agentpool: userpool
      containers:
      - image: jaygazulaboomi/v4:latest
        imagePullPolicy: Always
        name: atom-node
        ports:
        - name: http
          containerPort: 9090
          protocol: TCP
        - name: https
          containerPort: 9093
          protocol: TCP
        lifecycle:
          preStop:
            exec:
              command:
                - sh
                - /home/boomi/scaledown.sh
        resources:
          limits:
            cpu: "1000m"
            memory: "1536Mi"
          requests:
            cpu: "500m"
            memory: "1024Mi"
        volumeMounts:
          - mountPath: "/mnt/boomi"
            name: molecule-storage
          - name: tmpfs
            mountPath: "/run"
          - name: tmpfs
            mountPath: "/tmp"
          - name: cgroup
            mountPath: /sys/fs/cgroup
        startupProbe:
          timeoutSeconds: 90
          failureThreshold: 90
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - startup
        readinessProbe:
          timeoutSeconds: 60
          periodSeconds: 10
          initialDelaySeconds: 10
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - readiness
        livenessProbe:
          timeoutSeconds: 60
          periodSeconds: 60
          exec:
            command:
              - sh
              - /home/boomi/probe.sh
              - liveness
        env:
        - name: BOOMI_ATOMNAME
          value: "Boomi-AKS"
        - name: ATOM_LOCALHOSTID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: BOOMI_ACCOUNTID
          valueFrom:
            secretKeyRef:
              name: boomi-secret
              key: account
        - name: INSTALL_TOKEN
          valueFrom:
            secretKeyRef:
              name: boomi-secret
              key: token
        - name: BOOMI_CONTAINERNAME
          value: "$molecule_cluster_name"
        - name: INSTALLATION_DIRECTORY
          value: "/mnt/boomi"
        - name: CONTAINER_PROPERTIES_OVERRIDES
          value: "com.boomi.deployment.quickstart=True|com.boomi.container.is.orchestrated.container=true|com.boomi.container.cloudlet.findInitialHostsTimeout=5000|com.boomi.container.elasticity.asyncPollerTimeout=75000|com.boomi.container.elasticity.forceRestartOverride=50000"
EOF

kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/kubernetes/namespace.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/secrets.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolume.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolumeclam.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

if [ $boomi_auth == "token" ]
then
kubectl apply -f /tmp/statefulset_token.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
else
kubectl apply -f /tmp/statefulset_password.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
fi

kubectl apply -f https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/kubernetes/services.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/kubernetes/hpa.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

sleep 120

#kubectl apply -f https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/kubernetes/ingress.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/ingress.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

rm /tmp/secrets.yaml
