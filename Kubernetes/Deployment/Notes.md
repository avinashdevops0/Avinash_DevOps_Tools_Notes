# Kubernetes Deployments — Notes

## What is a Deployment?

A Deployment is a **higher-level controller** that manages a set of identical Pods. It ensures the desired number of Pod replicas are always running and handles rolling updates and rollbacks.

- Wraps a **ReplicaSet**, which in turn manages Pods
- You describe the **desired state**; the Deployment controller reconciles reality to match it
- Supports **zero-downtime rolling updates** and instant **rollbacks**
- The recommended way to run stateless applications in Kubernetes

```
Deployment → ReplicaSet → Pods
```

---

## Basic Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 3                      # Desired number of Pods
  selector:
    matchLabels:
      app: my-app                  # Must match template labels
  template:                        # Pod template
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "250m"
            memory: "64Mi"
          limits:
            cpu: "500m"
            memory: "128Mi"
```

> The `selector.matchLabels` must match `template.metadata.labels` — this is how the Deployment knows which Pods it owns.

---

## Key Spec Fields

| Field | Description |
|-------|-------------|
| `replicas` | Number of Pod copies to maintain (default: 1) |
| `selector` | Label query to identify owned Pods |
| `template` | Pod spec used to create new Pods |
| `strategy` | How updates are rolled out |
| `minReadySeconds` | Seconds a new Pod must be ready before counted as available |
| `revisionHistoryLimit` | Number of old ReplicaSets to keep for rollback (default: 10) |
| `progressDeadlineSeconds` | Seconds before a stalled rollout is marked failed (default: 600) |
| `paused` | If true, pauses the rollout |

---

## Update Strategies

### RollingUpdate (Default)

Gradually replaces old Pods with new ones. No downtime.

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1     # Max Pods that can be unavailable during update
      maxSurge: 1           # Max extra Pods above desired count during update
```

- `maxUnavailable` and `maxSurge` accept **integers** or **percentages** (e.g., `25%`)
- Default: `maxUnavailable: 25%`, `maxSurge: 25%`

**How it works:**
1. Creates new ReplicaSet with updated Pod template
2. Scales up new ReplicaSet while scaling down old one
3. Repeats until all Pods are replaced

### Recreate

Kills **all** existing Pods before creating new ones. Causes downtime.

```yaml
spec:
  strategy:
    type: Recreate
```

Use when your app cannot run two versions simultaneously (e.g., exclusive DB schema migrations).

---

## Rollout Commands

```bash
# Check rollout status
kubectl rollout status deployment/my-app

# View rollout history
kubectl rollout history deployment/my-app

# View a specific revision
kubectl rollout history deployment/my-app --revision=2

# Rollback to previous version
kubectl rollout undo deployment/my-app

# Rollback to a specific revision
kubectl rollout undo deployment/my-app --to-revision=2

# Pause a rollout
kubectl rollout pause deployment/my-app

# Resume a paused rollout
kubectl rollout resume deployment/my-app

# Restart all Pods (triggers rolling update)
kubectl rollout restart deployment/my-app
```

---

## Scaling

```bash
# Scale manually
kubectl scale deployment/my-app --replicas=5

# Scale via manifest
kubectl apply -f deployment.yaml   # With updated replicas field
```

### Horizontal Pod Autoscaler (HPA)

Automatically scales replicas based on CPU/memory or custom metrics:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70     # Scale up if avg CPU > 70%
```

```bash
# Create HPA imperatively
kubectl autoscale deployment my-app --min=2 --max=10 --cpu-percent=70

# View HPA
kubectl get hpa
```

> HPA requires the **Metrics Server** to be installed in the cluster.

---

## Updating a Deployment

### Update the image

```bash
# Imperative
kubectl set image deployment/my-app app=nginx:1.22

# Declarative (edit YAML and apply)
kubectl apply -f deployment.yaml

# Edit in-place
kubectl edit deployment/my-app
```

### Add a change-cause annotation (shows in rollout history)

```bash
kubectl annotate deployment/my-app kubernetes.io/change-cause="Upgraded nginx to 1.22"
```

---

## ReplicaSets

Deployments create and manage ReplicaSets automatically. You rarely interact with them directly, but it's useful to understand the relationship.

```bash
kubectl get replicasets
# NAME                  DESIRED   CURRENT   READY   AGE
# my-app-7d9f4b8c6d     3         3         3       10m   ← active
# my-app-5c6b9d4f2a     0         0         0       30m   ← old (kept for rollback)
```

- Each update creates a **new ReplicaSet**
- Old ReplicaSets are kept (scaled to 0) up to `revisionHistoryLimit`
- Rolling back restores a previous ReplicaSet to the desired replica count

---

## Deployment Conditions

`kubectl describe deployment` shows conditions that indicate health:

| Condition | Meaning |
|-----------|---------|
| `Available` | At least `minAvailable` Pods are ready |
| `Progressing` | Rollout is in progress or has completed |
| `ReplicaFailure` | A ReplicaSet failed to create a Pod |

A deployment is considered **failed** if it cannot make progress within `progressDeadlineSeconds`.

---

## Pod Template Best Practices in Deployments

### Always set resource requests/limits

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

### Always define readiness and liveness probes

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
```

### Use specific image tags — never `latest`

```yaml
image: nginx:1.21.6    # ✅ Pinned
image: nginx:latest    # ❌ Unpredictable
```

---

## Deployment vs Other Controllers

| Controller | Use Case |
|------------|----------|
| **Deployment** | Stateless apps, rolling updates, replicas |
| **StatefulSet** | Stateful apps needing stable identity/storage (DBs, queues) |
| **DaemonSet** | Run one Pod per node (log agents, monitoring) |
| **Job** | Run a task to completion once |
| **CronJob** | Run a Job on a schedule |

---

## Common kubectl Commands

```bash
# View
kubectl get deployments
kubectl get deploy -n <namespace> -o wide
kubectl describe deployment <name>

# Create / Update / Delete
kubectl apply -f deployment.yaml
kubectl create deployment my-app --image=nginx:1.21 --replicas=3
kubectl delete deployment <name>

# Scale
kubectl scale deployment/<name> --replicas=5

# Update image
kubectl set image deployment/<name> <container>=<image>:<tag>

# Rollout management
kubectl rollout status deployment/<name>
kubectl rollout history deployment/<name>
kubectl rollout undo deployment/<name>
kubectl rollout restart deployment/<name>

# Debug
kubectl get pods -l app=my-app
kubectl logs -l app=my-app --tail=50
kubectl get replicasets
```

---

## Best Practices

- Always use **Deployments** instead of bare Pods or ReplicaSets
- Pin **image tags** to specific versions — never use `latest`
- Set **resource requests and limits** on all containers
- Define **readiness probes** so traffic only reaches healthy Pods
- Use **RollingUpdate** with sensible `maxUnavailable`/`maxSurge` values
- Annotate updates with `kubernetes.io/change-cause` for clear rollout history
- Keep `revisionHistoryLimit` reasonable (3–5) to avoid excessive ReplicaSet clutter
- Use **HPA** for apps with variable load instead of manually scaling
- **Pause** a rollout before making multiple changes; resume once done
- Use **namespaces** and **labels** to organize Deployments across environments