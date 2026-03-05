# Kubernetes Services — Notes

## What is a Service?

A Service is a **stable network endpoint** that exposes a set of Pods. Since Pods are ephemeral and their IPs change, Services provide a consistent way to reach them.

- Services get a **stable virtual IP** (ClusterIP) that never changes
- Traffic is load-balanced across all matching Pods
- Pods are selected using **label selectors**
- DNS names are automatically assigned: `<service-name>.<namespace>.svc.cluster.local`

---

## How Services Find Pods

Services use **label selectors** to route traffic to matching Pods.

```yaml
# Pod has this label
metadata:
  labels:
    app: my-app

# Service selects Pods with that label
spec:
  selector:
    app: my-app
```

When a Pod's labels match, it is added to the Service's **Endpoints** list automatically. If no Pods match, the Service has no endpoints and traffic goes nowhere.

---

## Service Types

| Type | Accessible From | Use Case |
|------|----------------|----------|
| `ClusterIP` | Inside cluster only (default) | Internal service-to-service communication |
| `NodePort` | Outside cluster via node IP + port | Dev/testing, simple external access |
| `LoadBalancer` | Outside cluster via cloud load balancer | Production external traffic |
| `ExternalName` | Maps to an external DNS name | Redirect to external services |

---

## ClusterIP (Default)

Exposes the Service on an internal IP only. Only reachable from within the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: ClusterIP        # Default; can be omitted
  selector:
    app: my-app
  ports:
  - port: 80             # Port the Service listens on
    targetPort: 8080     # Port on the Pod/container
    protocol: TCP
```

Access inside cluster: `http://my-service` or `http://my-service.default.svc.cluster.local`

---

## NodePort

Exposes the Service on a static port on **every node** in the cluster. External traffic hits `<NodeIP>:<NodePort>`.

```yaml
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
  - port: 80             # ClusterIP port (internal)
    targetPort: 8080     # Pod port
    nodePort: 30080      # External port on node (30000–32767)
```

- `nodePort` is optional — Kubernetes assigns one automatically if omitted
- Valid range: **30000–32767**
- Not recommended for production (tied to node IPs, no built-in load balancing)

---

## LoadBalancer

Provisions an **external cloud load balancer** (AWS ELB, GCP LB, Azure LB). Builds on NodePort internally.

```yaml
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
```

After creation, `kubectl get svc` shows an `EXTERNAL-IP` once the cloud provider provisions it. Requires a cloud environment or a tool like MetalLB for bare-metal.

---

## ExternalName

Maps the Service to an **external DNS name** — no proxying or load balancing, just a CNAME.

```yaml
spec:
  type: ExternalName
  externalName: my-database.example.com
```

Useful for abstracting external dependencies (e.g., a managed database) behind a Service name inside the cluster.

---

## Headless Services

A Service with `clusterIP: None` — no virtual IP is assigned. DNS returns the **individual Pod IPs** directly instead.

```yaml
spec:
  clusterIP: None
  selector:
    app: my-app
```

Used with **StatefulSets** where clients need to address specific Pods (e.g., Kafka, Cassandra, etcd).

---

## Service YAML — Full Reference

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  namespace: default
  labels:
    app: my-app
spec:
  type: ClusterIP             # ClusterIP | NodePort | LoadBalancer | ExternalName
  selector:
    app: my-app               # Selects Pods with this label
  ports:
  - name: http
    protocol: TCP             # TCP (default) | UDP | SCTP
    port: 80                  # Port this Service exposes
    targetPort: 8080          # Port on the Pod (can also use named port)
  sessionAffinity: None       # None (default) | ClientIP
```

### Port Fields Explained

| Field | Description |
|-------|-------------|
| `port` | Port the Service listens on (what clients connect to) |
| `targetPort` | Port on the Pod that receives traffic |
| `nodePort` | Port on every node (NodePort/LoadBalancer types only) |
| `name` | Required if defining multiple ports |
| `protocol` | `TCP` (default), `UDP`, or `SCTP` |

---

## Named Ports

Instead of hardcoding port numbers in the Service, reference named ports from the Pod spec:

```yaml
# Pod
spec:
  containers:
  - name: app
    ports:
    - name: http
      containerPort: 8080

# Service
spec:
  ports:
  - port: 80
    targetPort: http    # References the named port
```

This decouples the Service from specific port numbers — changing the Pod's port only requires updating the Pod spec.

---

## DNS & Service Discovery

Kubernetes automatically creates DNS records for every Service.

| Record Type | Format | Resolves To |
|-------------|--------|-------------|
| A / AAAA | `<service>.<namespace>.svc.cluster.local` | ClusterIP |
| SRV | `_<port>._<proto>.<service>.<namespace>.svc.cluster.local` | Port + IP |
| CNAME | `<service>.<namespace>.svc.cluster.local` | ExternalName target |

**Shorthand resolution** (within same namespace):
- `my-service` → resolves to ClusterIP
- `my-service.other-namespace` → cross-namespace access

---

## Endpoints & EndpointSlices

Kubernetes automatically manages **Endpoints** objects that track the Pod IPs behind a Service.

```bash
kubectl get endpoints my-service
# NAME         ENDPOINTS                         AGE
# my-service   10.244.1.5:8080,10.244.2.3:8080   5m
```

**EndpointSlices** (v1.21+ default) replace Endpoints for better scalability — each slice holds up to 100 endpoints.

A Pod is added to endpoints when:
- Its labels match the Service selector
- Its `readinessProbe` passes (if defined)
- It is in `Running` phase

---

## Session Affinity

Route requests from the same client to the same Pod:

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 10800   # 3 hours (default)
```

Only `ClientIP` is supported (based on client's IP). Not a substitute for proper sticky sessions.

---

## Multi-Port Services

When a Pod exposes multiple ports, define them all in the Service (names are required):

```yaml
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
  - name: metrics
    port: 9090
    targetPort: 9090
```

---

## Services Without Selectors

You can create a Service without a selector and manage Endpoints manually — useful for pointing to external IPs or resources outside the cluster.

```yaml
# Service (no selector)
spec:
  ports:
  - port: 80
    targetPort: 5432

---
# Manual Endpoints
apiVersion: v1
kind: Endpoints
metadata:
  name: my-service       # Must match Service name
subsets:
- addresses:
  - ip: 192.168.1.100    # External server IP
  ports:
  - port: 5432
```

---

## Common kubectl Commands

```bash
# View
kubectl get services
kubectl get svc -n <namespace>
kubectl describe svc <service-name>

# Create / Delete
kubectl apply -f service.yaml
kubectl expose pod <pod-name> --port=80 --target-port=8080
kubectl expose deployment <name> --type=LoadBalancer --port=80
kubectl delete svc <service-name>

# Inspect endpoints
kubectl get endpoints <service-name>
kubectl get endpointslices

# Test connectivity (from inside cluster)
kubectl run test --image=busybox --rm -it -- wget -qO- http://my-service

# Port forward a service locally
kubectl port-forward svc/<service-name> 8080:80
```

---

## Ingress vs Service

Services handle **L4 (TCP/UDP)** routing. For **L7 (HTTP/HTTPS)** routing, use an **Ingress**:

| Feature | Service (LoadBalancer) | Ingress |
|---------|----------------------|---------|
| Protocol | TCP/UDP | HTTP/HTTPS |
| Host-based routing | No | Yes |
| Path-based routing | No | Yes |
| TLS termination | No | Yes |
| Cost | 1 LB per Service | 1 LB for all Services |

---

## Best Practices

- Prefer **ClusterIP** for internal services — only expose externally when needed
- Use **named ports** to decouple Services from hardcoded port numbers
- Always define **readiness probes** on Pods so unhealthy Pods are removed from endpoints
- Use **Ingress** instead of multiple LoadBalancer Services to reduce cloud LB costs
- Use **ExternalName** to abstract external dependencies behind an internal name
- Label Services consistently and match Pod labels carefully to avoid misrouting
- For StatefulSets, use a **headless Service** alongside a regular Service