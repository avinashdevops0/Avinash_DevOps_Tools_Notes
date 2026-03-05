# Kubernetes Pods — Notes

## What is a Pod?

A Pod is the **smallest deployable unit** in Kubernetes. It wraps one or more containers that share the same network namespace, storage volumes, and lifecycle.

- Each Pod gets a **unique cluster IP address**
- Containers inside a Pod communicate via `localhost`
- Pods are **ephemeral** — they are not self-healing; controllers recreate them
- A Pod always runs on a **single node**

---

## Pod Lifecycle

| Phase | Meaning |
|-------|---------|
| `Pending` | Accepted by the cluster; containers not yet running |
| `Running` | At least one container is running |
| `Succeeded` | All containers exited with code 0 |
| `Failed` | At least one container exited with a non-zero code |
| `Unknown` | Node communication lost |

### Container States
- **Waiting** — pulling image, waiting for secret, etc.
- **Running** — executing normally
- **Terminated** — finished (success or error)

### Restart Policies
| Policy | Behavior |
|--------|----------|
| `Always` | Restart on any exit (default) |
| `OnFailure` | Restart only on non-zero exit |
| `Never` | Never restart |

---

## Pod YAML Structure

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: my-app
spec:
  containers:
  - name: main
    image: nginx:1.21
    ports:
    - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
    env:
    - name: ENV_VAR
      value: "hello"
  restartPolicy: Always
```

### Key `spec` Fields

| Field | Purpose |
|-------|---------|
| `containers` | Main app containers |
| `initContainers` | Run before app containers (setup tasks) |
| `volumes` | Shared storage |
| `nodeSelector` | Schedule on specific nodes |
| `affinity` | Advanced scheduling rules |
| `tolerations` | Allow scheduling on tainted nodes |
| `serviceAccountName` | Pod identity for API access |
| `imagePullSecrets` | Credentials for private image registries |

---

## Init Containers

Run **sequentially** before app containers start. Each must complete successfully before the next begins.

```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox
    command: ['sh', '-c', 'until nc -z db 5432; do sleep 2; done']
  containers:
  - name: app
    image: my-app:latest
```

**Common uses:** wait for a dependency, run DB migrations, clone a repo, set up config files.

---

## Multi-Container Patterns

| Pattern | Idea | Example |
|---------|------|---------|
| **Sidecar** | Augments the main container | Log shipper, config reloader |
| **Ambassador** | Proxies traffic to/from main container | DB proxy, service mesh (Envoy) |
| **Adapter** | Normalizes output from main container | Metrics → Prometheus format |

All containers in the Pod share the same network and can share volumes.

---

## Resource Requests & Limits

```yaml
resources:
  requests:       # Minimum guaranteed; used for scheduling
    cpu: "250m"
    memory: "64Mi"
  limits:         # Maximum allowed
    cpu: "500m"
    memory: "128Mi"
```

- **CPU exceeded** → container is throttled
- **Memory exceeded** → container is OOMKilled

### QoS Classes
| Class | Condition | Priority |
|-------|-----------|----------|
| `Guaranteed` | requests == limits for all containers | Highest |
| `Burstable` | requests != limits for at least one container | Medium |
| `BestEffort` | No requests or limits set | Lowest (evicted first) |

### Units
- CPU: `1` = 1 core, `500m` = 0.5 cores, `250m` = 0.25 cores
- Memory: `Mi` = mebibytes, `Gi` = gibibytes

---

## Health Probes

| Probe | Question | Failure Action |
|-------|----------|----------------|
| `livenessProbe` | Is the container alive? | Restart container |
| `readinessProbe` | Ready to serve traffic? | Remove from Service endpoints |
| `startupProbe` | Has the app finished starting? | Kill container |

### Probe Methods
- `exec` — run a command; exit code `0` = healthy
- `httpGet` — HTTP GET; `2xx`/`3xx` = healthy
- `tcpSocket` — TCP connection check
- `grpc` — gRPC health check (v1.24+)

### Key Tuning Fields
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10   # Wait before first probe
  periodSeconds: 10         # How often to probe
  failureThreshold: 3       # Failures before action
  timeoutSeconds: 1         # Probe timeout
```

---

## Volumes & Storage

```yaml
spec:
  volumes:
  - name: my-data
    emptyDir: {}
  containers:
  - name: app
    volumeMounts:
    - name: my-data
      mountPath: /data
```

| Volume Type | Use Case |
|-------------|----------|
| `emptyDir` | Temporary; lives for Pod lifetime |
| `hostPath` | Mount from host node filesystem |
| `configMap` | Inject config files |
| `secret` | Inject sensitive data |
| `persistentVolumeClaim` | Durable persistent storage |
| `projected` | Combine multiple sources into one mount |

---

## Networking

- Every Pod gets a **unique IP** in the cluster
- Containers in a Pod share `localhost`
- Pods talk to each other via Pod IPs; **Services** provide stable virtual IPs
- **Network Policies** can restrict inter-Pod traffic

```yaml
# Rarely needed — use Services instead
ports:
- containerPort: 80    # Informational; what the container listens on
  hostPort: 8080       # Binds directly to node port (use sparingly)
```

---

## Scheduling

| Mechanism | Description |
|-----------|-------------|
| `nodeSelector` | Simple key-value node matching |
| Node Affinity | Rich expressions for required/preferred node selection |
| Pod Affinity/Anti-Affinity | Schedule relative to other Pods |
| Taints & Tolerations | Nodes repel Pods unless Pod tolerates the taint |
| Resource Requests | Scheduler ensures node has enough free resources |

```yaml
# Toleration example
tolerations:
- key: "dedicated"
  operator: "Equal"
  value: "gpu"
  effect: "NoSchedule"
```

---

## Common kubectl Commands

```bash
# View
kubectl get pods
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name>

# Create / Delete
kubectl apply -f pod.yaml
kubectl run my-pod --image=nginx
kubectl delete pod <pod-name>

# Logs & Debug
kubectl logs <pod-name>
kubectl logs <pod-name> -c <container>     # specific container
kubectl logs <pod-name> --previous         # crashed container
kubectl exec -it <pod-name> -- /bin/bash
kubectl exec <pod-name> -- <command>

# Resource usage
kubectl top pod <pod-name>

# Port forward
kubectl port-forward pod/<pod-name> 8080:80

# Events for a pod
kubectl get events --field-selector involvedObject.name=<pod-name>
```

---

## Best Practices

- Always set **resource requests and limits**
- Use **liveness + readiness probes** in production
- Don't run bare Pods — use **Deployments**, **StatefulSets**, or **DaemonSets**
- Use **labels** consistently for selection and organization
- Store config in **ConfigMaps**, secrets in **Secrets**
- Design containers to be **stateless**; use PVCs for persistent state
- Avoid `hostNetwork`, `hostPort`, and privileged containers unless necessary
- Aim for **Guaranteed QoS** for critical workloads
- Use **namespaces** to isolate environments