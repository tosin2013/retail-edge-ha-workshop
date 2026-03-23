#!/bin/bash
# =============================================================================
# Generate Bookbag Deployment Manifests for Multiple Students
# =============================================================================
# Usage: ./generate-bookbag-deployments.sh <student-count>
# Example: ./generate-bookbag-deployments.sh 50
# =============================================================================

set -e

STUDENT_COUNT=${1:-5}
OUTPUT_DIR="manifests/bookbag"
TEMPLATE_DIR="bookbag/deploy"

# Cluster configuration (update these for your environment)
CLUSTER_DOMAIN=${CLUSTER_DOMAIN:-"apps.cluster-ntq88.dynamic.redhatworkshops.io"}
CLUSTER_API=${CLUSTER_API:-"https://api.cluster-ntq88.dynamic.redhatworkshops.io:6443"}
BOOKBAG_IMAGE=${BOOKBAG_IMAGE:-"quay.io/tosin2013/retail-edge-ha-bookbag:latest"}

echo "==================================================================="
echo "Generating Bookbag Deployments for $STUDENT_COUNT Students"
echo "==================================================================="
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate deployment for each student
for i in $(seq -f "%02g" 1 $STUDENT_COUNT); do
  STUDENT_ID="$i"
  NAMESPACE="retail-edge-student-${i}"
  UDN_NAMESPACE="retail-edge-student-${i}-udn"
  STUDENT_USER="student-${i}"

  echo "Generating: bookbag-student-${i}.yaml"

  cat > "${OUTPUT_DIR}/bookbag-student-${i}.yaml" <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: bookbag
  namespace: ${NAMESPACE}
  labels:
    app: bookbag
    student-id: "${STUDENT_ID}"
    app.kubernetes.io/part-of: retail-edge-ha-workshop

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: bookbag-edit
  namespace: ${NAMESPACE}
  labels:
    app: bookbag
    student-id: "${STUDENT_ID}"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- kind: ServiceAccount
  name: bookbag
  namespace: ${NAMESPACE}

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bookbag
  namespace: ${NAMESPACE}
  labels:
    app: bookbag
    student-id: "${STUDENT_ID}"
    app.kubernetes.io/part-of: retail-edge-ha-workshop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bookbag
      student-id: "${STUDENT_ID}"
  template:
    metadata:
      labels:
        app: bookbag
        student-id: "${STUDENT_ID}"
    spec:
      serviceAccountName: bookbag
      containers:
      - name: terminal
        image: ${BOOKBAG_IMAGE}
        imagePullPolicy: Always
        env:
        - name: STUDENT_ID
          value: "${STUDENT_ID}"
        - name: STUDENT_NAMESPACE
          value: "${NAMESPACE}"
        - name: STUDENT_UDN_NAMESPACE
          value: "${UDN_NAMESPACE}"
        - name: STUDENT_USER
          value: "${STUDENT_USER}"
        - name: CLUSTER_DOMAIN
          value: "${CLUSTER_DOMAIN}"
        - name: CLUSTER_API
          value: "${CLUSTER_API}"
        - name: VM_USER
          value: "cloud-user"
        - name: VM_PASSWORD
          value: "redhat"
        - name: RHEL_NODE1
          value: "rhel-ha-node1"
        - name: RHEL_NODE2
          value: "rhel-ha-node2"
        - name: PACEMAKER_NET
          value: "pacemaker-net"
        - name: PACEMAKER_IP1
          value: "10.101.0.20"
        - name: PACEMAKER_IP2
          value: "10.101.0.21"
        - name: PACEMAKER_VIP
          value: "10.101.0.100"
        - name: MICROSHIFT_GW_A
          value: "microshift-gw-a"
        - name: MICROSHIFT_GW_B
          value: "microshift-gw-b"
        - name: MICROSHIFT_NET
          value: "microshift-net"
        - name: MICROSHIFT_IP_A
          value: "10.102.0.20"
        - name: MICROSHIFT_IP_B
          value: "10.102.0.21"
        - name: MICROSHIFT_VIP
          value: "10.102.0.100"
        - name: TWONODE_MASTER1
          value: "twonode-master1"
        - name: TWONODE_MASTER2
          value: "twonode-master2"
        - name: TWONODE_ARBITER
          value: "twonode-arbiter"
        - name: TWONODE_NET
          value: "twonode-net"
        - name: TWONODE_IP1
          value: "10.103.0.20"
        - name: TWONODE_IP2
          value: "10.103.0.21"
        - name: TWONODE_IP_ARBITER
          value: "10.103.0.22"
        - name: AUTH_USERNAME
          value: "${STUDENT_USER}"
        - name: AUTH_PASSWORD
          value: "openshift"
        ports:
        - containerPort: 10080
          protocol: TCP
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /workshop/
            port: 10080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /workshop/
            port: 10080
          initialDelaySeconds: 10
          periodSeconds: 5

---
apiVersion: v1
kind: Service
metadata:
  name: bookbag
  namespace: ${NAMESPACE}
  labels:
    app: bookbag
    student-id: "${STUDENT_ID}"
    app.kubernetes.io/part-of: retail-edge-ha-workshop
spec:
  type: ClusterIP
  ports:
  - port: 10080
    targetPort: 10080
    protocol: TCP
    name: http
  selector:
    app: bookbag
    student-id: "${STUDENT_ID}"

---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: bookbag
  namespace: ${NAMESPACE}
  labels:
    app: bookbag
    student-id: "${STUDENT_ID}"
    app.kubernetes.io/part-of: retail-edge-ha-workshop
spec:
  to:
    kind: Service
    name: bookbag
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

done

echo ""
echo "==================================================================="
echo "Generation Complete!"
echo "==================================================================="
echo ""
echo "Generated Files:"
echo "  Location: ${OUTPUT_DIR}/"
echo "  Count: ${STUDENT_COUNT} deployment manifests"
echo ""
echo "Deploy for all students:"
echo "  for i in {01..${STUDENT_COUNT}}; do"
echo "    oc apply -f ${OUTPUT_DIR}/bookbag-student-\${i}.yaml"
echo "  done"
echo ""
echo "Get student URLs:"
echo "  oc get routes -A | grep bookbag"
echo ""
