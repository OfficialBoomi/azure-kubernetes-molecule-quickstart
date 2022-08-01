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
    --boomi_molecule_name)
      boomi_molecule_name="$1"
      shift
      ;;
    --fileshare)
      fileshare="$1"
      shift
      ;;
    --pod_cpu)
      pod_cpu="$1"
      shift
      ;;
    --pod_memory)
      pod_memory="$1"
      shift
      ;;
    --pv_size)
      pv_size="$1"
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

if [ $boomi_auth == "Token" ]
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
    storage: $pv_size
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
      storage: $pv_size
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
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "$appgw_ssl_cert"
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
              number: 9093
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
      terminationGracePeriodSeconds: 900
      volumes:
        - name: molecule-storage
          persistentVolumeClaim:
            claimName: molecule-storage
      nodeSelector:
        agentpool: userpool
      securityContext:
        fsGroup: 1000 
      containers:
      - image: boomi/molecule:4.2.0
        imagePullPolicy: Always
        name: atom-node
        ports:
        - containerPort: 9090
          protocol: TCP
        - containerPort: 9093
          protocol: TCP
        lifecycle:
          preStop:
            exec:
              command:
                - sh
                - /home/boomi/scaledown.sh
        resources:
          limits:
            cpu: $pod_cpu
            memory: $pod_memory
          requests:
            cpu: "500m"
            memory: "768Mi"
        volumeMounts:
          - name: molecule-storage
            mountPath: "/mnt/boomi"
        readinessProbe:
          periodSeconds: 10
          initialDelaySeconds: 10
          httpGet:
            path: /_admin/readiness
            port: 9090
        livenessProbe:
          periodSeconds: 60
          httpGet:
            path: /_admin/liveness
            port: 9090
        env:
        - name: BOOMI_ATOMNAME
          value: "$boomi_molecule_name"
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
        - name: CONTAINER_PROPERTIES_OVERRIDES
          value: "com.boomi.container.debug=false|com.boomi.deployment.quickstart=true"
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
      terminationGracePeriodSeconds: 900
      volumes:
        - name: molecule-storage
          persistentVolumeClaim:
            claimName: molecule-storage
      nodeSelector:
        agentpool: userpool
      securityContext:
        fsGroup: 1000
      containers:
      - image: boomi/molecule:4.2.0
        imagePullPolicy: Always
        name: atom-node
        ports:
        - containerPort: 9090
          protocol: TCP
        - containerPort: 9093
          protocol: TCP
        lifecycle:
          preStop:
            exec:
              command:
                - sh
                - /home/boomi/scaledown.sh
        resources:
          limits:
            cpu: $pod_cpu
            memory: $pod_memory
          requests:
            cpu: "500m"
            memory: "768Mi"
        volumeMounts:
          - name: molecule-storage
            mountPath: "/mnt/boomi"
        readinessProbe:
          periodSeconds: 10
          initialDelaySeconds: 10
          httpGet:
            path: /_admin/readiness
            port: 9090
        livenessProbe:
          periodSeconds: 60
          httpGet:
            path: /_admin/liveness
            port: 9090
        env:
        - name: BOOMI_ATOMNAME
          value: "$boomi_molecule_name"
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
        - name: CONTAINER_PROPERTIES_OVERRIDES
          value: "com.boomi.container.debug=false|com.boomi.deployment.quickstart=true"
EOF

cat >/tmp/namespace.yaml <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: aks-boomi-molecule
  labels:
    name: aks-boomi-molecule
EOF

cat >/tmp/services.yaml <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: molecule-service
  labels:
    app: molecule
spec:
  selector:
    app: molecule
  ports:
  - protocol: TCP
    port: 9093
    targetPort: 9090
EOF

cat >/tmp/hpa.yaml <<EOF
---
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: molecule-hpa
  labels:
    app: molecule
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 30
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 10
        periodSeconds: 15
      selectPolicy: Min
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 30
        periodSeconds: 30
      - type: Pods
        value: 10
        periodSeconds: 15
      selectPolicy: Max
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: molecule
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
EOF


kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/namespace.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/secrets.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolume.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolumeclam.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

if [ $boomi_auth == "Token" ]
then
kubectl apply -f /tmp/statefulset_token.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
else
kubectl apply -f /tmp/statefulset_password.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config
fi

kubectl apply -f /tmp/services.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/hpa.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

sleep 120

kubectl apply -f /tmp/ingress.yaml --namespace=aks-boomi-molecule --kubeconfig=/root/.kube/config

rm /tmp/secrets.yaml
