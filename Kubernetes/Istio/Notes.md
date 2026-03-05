# Kubernetes + Istio Traffic Management
### Detailed Notes: Canary Deployment with Weighted Routing

---

## 1. Overview

This configuration sets up a Kubernetes application with an **Istio service mesh** for intelligent traffic routing between two versions of a web app. It demonstrates a classic **canary deployment** pattern using a 50/50 traffic split.

| Field | Value |
|---|---|
| Deployment Type | Canary / Blue-Green Hybrid |
| Traffic Split | 50% v1 / 50% v2 |
| Mesh Used | Istio Service Mesh |
| Service Type | LoadBalancer (external) |
| Protocol | HTTP (TCP port 80) |
| Container Port | 80 |

---

## 2. Deployments

Two separate Kubernetes Deployments are defined, each running a different version of the web application. They share the same `app` label but differ in the `version` label — the key Istio uses to distinguish traffic subsets.

### 2.1 `deploy-1` — Version v1

```yaml
name: deploy-1
image: avinashg0/water
labels: app: web, version: v1
replicas: 1
containerPort: 80
```

| Field | Detail |
|---|---|
| Name | `deploy-1` |
| Replicas | 1 |
| Image | `avinashg0/water` |
| Labels | `app: web`, `version: v1` |
| Container Port | 80 |

**Key Points:**
- `avinashg0/water` is the **stable baseline** (v1) application
- `matchLabels` uses **both** `app: web` and `version: v1` to ensure the Deployment manages only its own Pods
- Template labels are propagated to all spawned Pods — these labels are what Istio's DestinationRule reads

### 2.2 `deploy-2` — Version v2

```yaml
name: deploy-2
image: avinashg0/movie-tickets
labels: app: web, version: v2
replicas: 1
containerPort: 80
```

| Field | Detail |
|---|---|
| Name | `deploy-2` |
| Replicas | 1 |
| Image | `avinashg0/movie-tickets` |
| Labels | `app: web`, `version: v2` |
| Container Port | 80 |

**Key Points:**
- `avinashg0/movie-tickets` is the **new canary version** receiving test traffic
- Structurally identical to `deploy-1` — only the image and `version` label differ
- Both deployments use the same container name `cont-1` (not ideal; use descriptive names in production)

> ⚠️ **Note:** With only 1 replica per version, a single Pod crash means 0% traffic to that version. Increase replicas in production.

---

## 3. Kubernetes Service

The Service is the **single entry point** for all traffic. It selects Pods from **both deployments** because its selector only matches `app: web` — intentionally ignoring the `version` label.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: LoadBalancer
  selector:
    app: web        # Matches BOTH v1 and v2 pods
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

| Field | Detail |
|---|---|
| Name | `web` |
| Type | `LoadBalancer` |
| Selector | `app: web` (matches both v1 and v2 Pods) |
| External Port | 80 |
| Target Port | 80 |

**Key Points:**
- **Without Istio:** the Service would randomly load-balance across ALL matched Pods (v1 + v2 together)
- **With Istio:** the VirtualService intercepts traffic and applies weighted rules *before* native K8s load balancing
- `LoadBalancer` type provisions an external cloud load balancer (AWS ELB, GCP LB, etc.)
- The Service name `web` is what DestinationRule and VirtualService reference via the `host` field

> 💡 The selector omitting `version` is intentional — it lets Istio own the routing logic between versions.

---

## 4. Istio DestinationRule

The DestinationRule **defines named subsets** of the service's Pods based on label selectors. These subsets are the targets referenced by the VirtualService.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: web
spec:
  host: web           # Must match the K8s Service name exactly
  subsets:
    - name: v1
      labels:
        version: v1   # Selects Pods with this label → deploy-1 pods
    - name: v2
      labels:
        version: v2   # Selects Pods with this label → deploy-2 pods
```

| Field | Detail |
|---|---|
| API Version | `networking.istio.io/v1beta1` |
| Host | `web` (matches the K8s Service name) |
| Subset `v1` selector | `version: v1` |
| Subset `v2` selector | `version: v2` |

**How Subsets Work:**
- `subset: v1` → resolves to Pods from `deploy-1` (labeled `version: v1`)
- `subset: v2` → resolves to Pods from `deploy-2` (labeled `version: v2`)
- Subsets can also carry **traffic policies** (connection pools, TLS mode, load balancing algorithm) — none are defined here, so defaults apply
- Without a DestinationRule, the VirtualService **cannot reference subsets** and routing will fail

---

## 5. Istio VirtualService

The VirtualService is the **traffic routing brain**. It intercepts all HTTP requests to the `web` host and distributes them between subsets according to defined weights.

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: web
spec:
  hosts:
    - web
  http:
    - route:
        - destination:
            host: web
            subset: v1
          weight: 50      # 50% of traffic → v1
        - destination:
            host: web
            subset: v2
          weight: 50      # 50% of traffic → v2
```

| Field | Detail |
|---|---|
| Host | `web` |
| Routing Type | HTTP weighted routing |
| v1 Weight | 50% |
| v2 Weight | 50% |

**Key Points:**
- Routing happens at the **Envoy sidecar proxy level** — before requests reach application containers
- `weights` must always **sum to 100**; Istio rejects the config otherwise
- The VirtualService references subset names defined in the DestinationRule — they must match exactly
- You can add **retries, timeouts, fault injection, header-based routing** in the `http` block — none are set here

> 💡 To roll out gradually, just update the weights: `90/10` → `70/30` → `50/50` → `20/80` → `0/100`

---

## 6. End-to-End Traffic Flow

```
Client Request (HTTP :80)
        │
        ▼
┌──────────────────┐
│  LoadBalancer    │  ← Cloud LB (AWS ELB / GCP LB)
│  Service (web)   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Istio Envoy     │  ← Sidecar proxy intercepts traffic
│  Sidecar Proxy   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  VirtualService  │  ← Applies 50/50 weight rule
│  (web)           │
└──────┬─────┬─────┘
       │     │
   50% │     │ 50%
       ▼     ▼
┌──────────┐ ┌──────────┐
│ subset:v1│ │ subset:v2│  ← DestinationRule resolves subsets
│(deploy-1)│ │(deploy-2)│
│  :water  │ │ :movie-  │
│          │ │  tickets │
└──────────┘ └──────────┘
```

| Step | Component | Action |
|---|---|---|
| 1 | External Client | Sends HTTP request to LoadBalancer IP on port 80 |
| 2 | LoadBalancer Service | Routes request into the cluster |
| 3 | Istio Envoy Sidecar | Intercepts the request |
| 4 | VirtualService | Applies 50/50 weight rule, selects destination subset |
| 5 | DestinationRule | Resolves subset name to matching Pod labels |
| 6 | Pod (v1 or v2) | Handles the HTTP request on port 80 |
| 7 | Response | Travels back through Envoy proxy to the client |

---

## 7. Canary Deployment Pattern

This is a textbook **canary deployment** — a technique where a new version is gradually rolled out to a subset of users before fully replacing the old version.

### Typical Rollout Progression

| Phase | v1 Weight | v2 Weight | Purpose |
|---|---|---|---|
| Initial | 100% | 0% | All traffic on stable v1 |
| Canary Start | 90% | 10% | Small test — monitor errors/latency |
| Expanding | 70% | 30% | Growing confidence in v2 |
| **Current Config** | **50%** | **50%** | **Equal split — active comparison** |
| Near Complete | 20% | 80% | Majority on v2, v1 as fallback |
| Full Rollout | 0% | 100% | v2 fully deployed, v1 retired |

### Rollback Strategy
If v2 shows issues, rollback is instant — just update the VirtualService weights:
```yaml
# Emergency rollback: send all traffic back to v1
- destination:
    host: web
    subset: v1
  weight: 100
```

---

## 8. Key Concepts

### 8.1 Istio Service Mesh
- Istio adds **observability, security, and traffic management** to Kubernetes without code changes
- Works by injecting an **Envoy sidecar proxy** into every Pod, intercepting all traffic
- The control plane (`istiod`) manages config and distributes it to all Envoy proxies
- Operates transparently at the **infrastructure level**

### 8.2 DestinationRule vs VirtualService

| Resource | Responsibility |
|---|---|
| **VirtualService** | **WHERE** traffic goes (routing rules, weights, retries, timeouts, fault injection) |
| **DestinationRule** | **HOW** traffic reaches the destination (subsets, load balancing algorithm, TLS, connection pools) |

### 8.3 The Label Selector Chain

```
Pod Labels (version: v1 / v2)
        ↑
DestinationRule subsets select Pods via labels
        ↑
VirtualService routes to named subsets
        ↑
Client traffic hits the VirtualService host
```

> If Pod labels are wrong or missing, the entire routing chain silently breaks.

### 8.4 Why LoadBalancer + Istio Together?

The native K8s Service with `type: LoadBalancer` provides external access. Istio's VirtualService then takes over internal routing logic. In a production setup, you'd typically replace the LoadBalancer Service with an **Istio IngressGateway** for full mesh-level control over external traffic.

---

## 9. Limitations & Improvements

### Current Limitations

| Issue | Impact |
|---|---|
| Single replica per version | No HA — one crash = version goes dark |
| No `readinessProbe` / `livenessProbe` | Broken Pods may still receive traffic |
| No resource `requests` / `limits` | Pods can starve or consume unbounded resources |
| Raw `LoadBalancer` type | Bypasses Istio IngressGateway; less control |
| No mTLS policy | Intra-mesh traffic is unencrypted |
| No retries / timeouts in VirtualService | Transient failures not handled automatically |
| No HPA | No auto-scaling under load |

### Recommended Improvements

```yaml
# 1. Add health checks
readinessProbe:
  httpGet:
    path: /health
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 10

# 2. Add resource limits
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# 3. Enforce mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
spec:
  mtls:
    mode: STRICT

# 4. Add retries in VirtualService
retries:
  attempts: 3
  perTryTimeout: 5s
  retryOn: 5xx,reset,connect-failure
```

---

## 10. Quick Reference

### kubectl Commands

```bash
# Apply the full configuration
kubectl apply -f config.yaml

# Check deployment and pod status
kubectl get deployments
kubectl get pods --show-labels

# Verify Istio resources
kubectl get virtualservice,destinationrule

# Describe routing rules
kubectl describe virtualservice web
kubectl describe destinationrule web

# Edit traffic weights live
kubectl edit virtualservice web

# Watch pod logs (both versions)
kubectl logs -l app=web -f

# Check Envoy proxy config
istioctl proxy-config routes deploy/deploy-1

# Validate Istio config
istioctl analyze
```

### Resource Dependency Summary

```
deploy-1 (version: v1) ──┐
                          ├──► Service (web) ──► DestinationRule (web) ──► VirtualService (web)
deploy-2 (version: v2) ──┘
```

All 5 resources must be present and consistent for weighted routing to work correctly.

---

*Kubernetes + Istio Traffic Management Notes*