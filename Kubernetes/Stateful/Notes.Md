# Kubernetes StatefulSets — Notes

## What is a StatefulSet?

A StatefulSet is a controller for managing **stateful applications** — workloads that need stable identity, ordered operations, or persistent storage. Unlike Deployments, each Pod in a StatefulSet has a **unique, persistent identity** that survives rescheduling.

- Pods get **stable, predictable names**: `<name>-0`, `<name>-1`, `<name>-2`, ...
- Each Pod gets its own **PersistentVolumeClaim** (not shared)
- Pods are created, updated, and deleted in **strict order**
- Stable **network identity** via a Headless Service

**Common use cases:** databases (MySQL, PostgreSQL), distributed systems (Kafka, Zookeeper, etcd, Cassandra), message queues, any app that maintains per-instance state.

---

## StatefulSet vs Deployment

| Feature | Deployment | StatefulSet |
|---------|------------|-------------|
| Pod names | Random suffix (`my-app-7d9f4b`) | Ordered index (`my-app-0`) |
| Pod identity | Interchangeable | Unique and stable |
| Storage | Shared or none | Per-Pod PVC |
| Start/stop order | Parallel (default) | Sequential |
| Use case | Stateless apps | Stateful apps |
| Rolling update order | Random | Reverse order (N→0) |

---

## Basic StatefulSet YAML

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: my-db
spec:
  serviceName: my-db-headless        # Must match a Headless Service
  replicas: 3
  selector:
    matchLabels:
      app: my-db
  template:
    metadata:
      labels:
        app: my-db
    spec:
      containers:
      - name: db
        image: postgres:15
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
  volumeClaimTemplates:              # Per-Pod PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: standard
      resources:
        requests:
          storage: 10Gi
```

---

## Headless Service (Required)

A StatefulSet **requires** a Headless Service to give each Pod a stable DNS name. Without it, Pod-level DNS doesn't work.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-db-headless
spec:
  clusterIP: None             # Makes it headless
  selector:
    app: my-db
  ports:
  - port: 5432
    targetPort: 5432
```

### DNS Names per Pod

Each Pod gets a DNS record in the format:

```
<pod-name>.<service-name>.<namespace>.svc.cluster.local
```

| Pod | DNS Name |
|-----|----------|
| `my-db-0` | `my-db-0.my-db-headless.default.svc.cluster.local` |
| `my-db-1` | `my-db-1.my-db-headless.default.svc.cluster.local` |
| `my-db-2` | `my-db-2.my-db-headless.default.svc.cluster.local` |

This allows replicas to discover and communicate with each other by name — essential for leader election, replication, and clustering.

---

## Pod Identity & Naming

Pods are named `<statefulset-name>-<ordinal>` starting from `0`:

```bash
kubectl get pods
# NAME       READY   STATUS    RESTARTS   AGE
# my-db-0    1/1     Running   0          10m
# my-db-1    1/1     Running   0          9m
# my-db-2    1/1     Running   0          8m
```

- If `my-db-1` is deleted, Kubernetes recreates it with the **same name**, same PVC, and same DNS name
- The ordinal index is permanent for the lifetime of the StatefulSet

---

## VolumeClaimTemplates

The key difference from Deployments — each Pod gets its **own PVC** created from the template.

```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: fast-ssd
    resources:
      requests:
        storage: 20Gi
```

### PVC Naming

PVCs are named `<volume-name>-<pod-name>`:

| Pod | PVC Created |
|-----|-------------|
| `my-db-0` | `data-my-db-0` |
| `my-db-1` | `data-my-db-1` |
| `my-db-2` | `data-my-db-2` |

> **Important:** Deleting a StatefulSet does **not** delete its PVCs. You must delete them manually. This protects data from accidental loss.

```bash
kubectl delete pvc data-my-db-0 data-my-db-1 data-my-db-2
```

---

## Pod Management Policies

Controls whether Pods are managed sequentially or in parallel.

```yaml
spec:
  podManagementPolicy: OrderedReady    # Default
```

| Policy | Behavior |
|--------|----------|
| `OrderedReady` | Pods created/deleted one at a time, in order. Each must be Ready before the next starts. |
| `Parallel` | Pods created/deleted simultaneously (like a Deployment). Identity and storage still stable. |

Use `Parallel` when your app handles its own coordination and you don't need strict ordering.

---

## Update Strategies

### RollingUpdate (Default)

Updates Pods one at a time in **reverse ordinal order** (highest index first): `N-1 → ... → 1 → 0`.

```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0           # Only Pods with ordinal >= partition are updated
```

### Partition — Canary Releases

The `partition` field lets you do a **staged rollout**:

```yaml
rollingUpdate:
  partition: 2     # Only my-db-2 gets the new version; my-db-0 and my-db-1 stay on old
```

Gradually lower the partition to roll out to more Pods.

### OnDelete

Pods are only updated when **manually deleted**. Gives full control over when each Pod restarts.

```yaml
spec:
  updateStrategy:
    type: OnDelete
```

---

## Scaling StatefulSets

```bash
# Scale up
kubectl scale statefulset my-db --replicas=5

# Scale down
kubectl scale statefulset my-db --replicas=2
```

**Scaling up:** new Pods are created sequentially (`3 → 4 → 5`), each waiting for the previous to be Ready.

**Scaling down:** Pods are terminated in reverse order (`5 → 4 → 3`). PVCs are **not** deleted.

---

## Deletion Behavior

```bash
# Delete the StatefulSet (Pods are deleted, PVCs are NOT)
kubectl delete statefulset my-db

# Delete without waiting (non-cascading — Pods become orphaned, managed manually)
kubectl delete statefulset my-db --cascade=orphan

# Delete PVCs separately
kubectl delete pvc -l app=my-db
```

---

## Key Spec Fields

| Field | Description |
|-------|-------------|
| `serviceName` | Name of the governing Headless Service (required) |
| `replicas` | Desired number of Pods |
| `selector` | Must match `template.metadata.labels` |
| `template` | Pod template |
| `volumeClaimTemplates` | PVC template; one PVC per Pod |
| `podManagementPolicy` | `OrderedReady` or `Parallel` |
| `updateStrategy` | `RollingUpdate` or `OnDelete` |
| `revisionHistoryLimit` | Old ReplicaSets kept for rollback (default: 10) |
| `minReadySeconds` | Seconds a Pod must be Ready before counted available |

---

## Common Patterns

### Primary + Replicas (e.g., MySQL, PostgreSQL)

- `my-db-0` is always the **primary** (write node)
- `my-db-1`, `my-db-2` are **read replicas**
- Init container or app logic bootstraps replication using stable DNS names
- Clients write to `my-db-0.my-db-headless`, read from any Pod via a regular Service

### Clustered Systems (e.g., Kafka, Zookeeper)

- Each broker/node has a stable ID tied to its ordinal
- Nodes discover each other via headless DNS names
- Config references peers by DNS: `my-kafka-0.my-kafka-headless`, `my-kafka-1.my-kafka-headless`, etc.

---

## Common kubectl Commands

```bash
# View
kubectl get statefulsets
kubectl get sts                              # Short alias
kubectl describe sts <name>
kubectl get pods -l app=my-db

# Create / Delete
kubectl apply -f statefulset.yaml
kubectl delete sts <name>                    # PVCs remain

# Scale
kubectl scale sts <name> --replicas=5

# Rollout
kubectl rollout status sts/<name>
kubectl rollout history sts/<name>
kubectl rollout undo sts/<name>

# Inspect PVCs
kubectl get pvc -l app=my-db

# Exec into a specific Pod
kubectl exec -it my-db-0 -- /bin/bash

# Restart (triggers rolling update)
kubectl rollout restart sts/<name>
```

---

## Best Practices

- Always pair a StatefulSet with a **Headless Service** for stable DNS
- Also create a **regular ClusterIP Service** for client access (load-balanced reads)
- Use **`OrderedReady`** unless your app manages its own coordination
- Never share a PVC between StatefulSet Pods — use `volumeClaimTemplates`
- Use **`partition`** for safe, staged rollouts of stateful workloads
- Set proper **resource requests and limits** — stateful apps are often resource-intensive
- Define **readiness probes** carefully — ordering depends on Pods becoming Ready
- Remember that **deleting a StatefulSet does not delete PVCs** — clean up manually
- For databases, consider **operator patterns** (e.g., CloudNativePG, Strimzi) which add lifecycle management on top of StatefulSets
- Use **pod disruption budgets (PDBs)** to ensure quorum is maintained during node maintenance