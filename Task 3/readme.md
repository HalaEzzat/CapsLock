# Incident Analysis: Symfony API 500 Internal Server Error:

- **Problem** : Users report that the Symfony API deployed in Kubernetes is returning 500 Internal Server Error. <br/>
- **Stack** : PHP-FPM (Symfony), Kubernetes (GKE), Ingress + Service, Helm deployment, Grafana + Loki + Prometheus monitoring.
---
### Step-by-Step Plan to Diagnose and Localize the Issue
- The approach follows a "top-down" or "outside-in" methodology, starting from what the user sees and moving deeper into the stack.<br/>

**Phase 1: Initial Triage & System Health Check (5-10 minutes)**
1. Verify Scope & Impact:
   - Confirm the error is widespread (not just one user).
   - Check if other services/APIs are affected.
   - Are all endpoints returning 500s, or just specific ones?
   - When did the issue start? Correlate with recent deployments or changes.
2. Check Monitoring Dashboards (Grafana):
   - **Application Metrics**: Look at the Symfony API's specific dashboards. Are there spikes in 5xx errors? Drops in successful requests? Latency spikes?
   - **System Metrics (Prometheus)**: Check CPU, Memory, Network I/O for the affected pods/nodes. Are there resource saturation issues?
   - **Kubernetes Metrics**: Node health, pod restarts, deployment status.
   - **Alerts**: Are there any active alerts from Prometheus that might indicate a root cause (e.g., high error rate, low replica count, OOMKilled pods)?
3. Recent Changes Review:
   - Check recent Helm deployments (helm history). Was there a new version deployed just before the incident?
   - Check recent Git commits for the application or infrastructure.

**Phase 2: Network & Kubernetes Layer Investigation (10-20 minutes)**

1. Ingress Health:
   - Verify the Ingress controller is healthy and serving traffic.
   - Check Ingress rules for the affected API.
2. Service Health:
   - Confirm the Kubernetes Service is pointing to the correct Deployment/Pods.
   - Check if the Service has healthy endpoints.
3. Deployment & Pod Health:
   - Are the expected number of replicas running?
   - Are any pods in a `CrashLoopBackOff`, `Pending`, or `Error` state?
   - Are pods frequently restarting?
   - Check pod resource usage (CPU/Memory) against requests/limits. Are they hitting limits?

**Phase 3: Application & Container Layer Deep Dive (20-40 minutes)**

1. Application Logs (Loki):
   - This is typically where the "500" error's true nature is revealed.
   - Filter logs for the affected service and time range.
   - Look for PHP-FPM errors, Symfony exceptions, database connection errors, file permission issues, memory exhaustion errors, or any unhandled exceptions.
   - Pay attention to logs immediately preceding the 500 errors.
2. Container Status & Processes:
   - If logs are inconclusive, check the running processes inside a problematic pod. Is PHP-FPM running? Is Nginx (if co-located) running?
3. Connectivity from Pod:
   - Attempt to curl internal services (e.g., database, cache) from within the affected pod to rule out network connectivity issues from the application.
4. Configuration Verification:
   - Check environment variables (kubectl describe pod). Are sensitive values or database credentials correctly passed?
   - Verify ConfigMaps and Secrets mounted to the pod.
---
- **Commands and Tools Used for Investigation**
1. Kubernetes (kubectl):
   - kubectl get deployments -n <namespace>: Check deployment status.
   - kubectl get pods -l app=<app-name> -n <namespace>: List pods for the application.
   - kubectl describe pod <pod-name> -n <namespace>: Get detailed information about a pod, including events, resource usage, and environment variables. Crucial for seeing OOMKilled events or failed probes.
   - kubectl logs <pod-name> -n <namespace> -f --tail=100: Stream logs from a specific pod.
   - kubectl top pod <pod-name> -n <namespace>: Check real-time CPU/memory usage of a pod.
   - kubectl exec -it <pod-name> -n <namespace> -- bash: Get a shell inside the container for deeper investigation (e.g., check file system, run curl, php -v, composer diagnose).
   - kubectl get events -n <namespace>: See cluster-level events that might affect pods (e.g., node pressure, scheduler issues).
   - kubectl get ingress -n <namespace>: Check Ingress status and rules.
   - kubectl get service -n <namespace>: Check Service status and endpoints.
2. Helm:
   - helm list -n <namespace>: List deployed Helm releases.
   - helm history <release-name> -n <namespace>: See deployment history.
   - helm get values <release-name> -n <namespace>: Retrieve current values used for the deployment.
3. Monitoring (Grafana, Loki, Prometheus):
   - Grafana Dashboards: Visualizing metrics (error rates, latency, resource usage, pod restarts).
   - Loki Query Language (LogQL): For querying and filtering application logs (e.g., {job="symfony-api", container="php-fpm"} |= "CRITICAL", {job="symfony-api"} |= "exception").
   - Prometheus Alert Manager: Check active alerts.
   - Prometheus UI/PromQL: Directly query metrics if needed (e.g., sum(rate(http_requests_total{job="symfony-api", status_code="5xx"}[5m]))).
4. Networking Tools:
   - curl -v <ingress-url>/<api-endpoint>: Test external connectivity and see HTTP headers.
   - curl -v <service-name>:<port>/<api-endpoint> (from within another pod): Test internal service connectivity.
5. Application-Specific Tools (via kubectl exec):
   - php -m: Check loaded PHP extensions.
   - php -i: Full PHP info.
   - php bin/console cache:clear: Clear Symfony cache (if applicable and safe).
   - php bin/console doctrine:schema:validate: Validate database schema (if using Doctrine).
   - ping <database-host>: Basic network reachability.
---
**Isolating Infrastructure vs. Application Issue**
> The key is to determine where the failure point lies in the request flow.<br/>

1. Infrastructure Issue (Kubernetes, Network, Resources):
   - Symptoms:
     - Pods are not running, stuck in Pending, or CrashLoopBackOff before the application even starts.
     - Pods are OOMKilled (Out Of Memory Killed) or CPU throttled.
     - Service has no healthy endpoints.
     - Ingress is not routing traffic correctly (e.g., 404 from Ingress controller, or request never reaches the service).
     - Network policies are blocking traffic.
     - Node issues (disk full, unhealthy, not ready).
   - Isolation Steps:
     - Can kubectl get pods see healthy pods? If not, it's likely infra (scheduler, node, image pull).
     - Can kubectl describe pod show the container starting successfully? Look for Readiness and Liveness probe failures. If probes fail, it's infra reporting an issue, but the root might still be app.
     - Can kubectl exec into the container? If yes, the container is running.
     - From inside the container, can you curl the database or other external dependencies? If not, it's a network/DNS issue within the cluster.
     - Are resource requests/limits being hit? kubectl top and Grafana metrics will show this. If so, it's an infrastructure resource constraint.
2. Application Issue (PHP-FPM, Symfony Code, Dependencies):
   - Symptoms:
     - Pods are running and healthy from Kubernetes' perspective (probes pass initially).
     - Traffic reaches the pod, but the application within the container returns 500.
     - Application logs (Loki) show specific PHP errors, unhandled exceptions, database connection failures (from the app's perspective), or misconfigurations.
     - The issue might only occur for specific endpoints or under certain load conditions.
   - Isolation Steps:
     - Confirm traffic reaches the pod: Use kubectl logs on the Nginx/proxy container (if separate) or PHP-FPM container to see if requests are being received.
     - Analyze application logs (Loki): This is the primary source. If you see PHP Fatal Errors, try/catch blocks not handling exceptions, database connection errors, etc., it's an application issue.
     - Reproduce locally (if possible): If the code is the same, try to run the problematic request against a local dev environment to see if the error is reproducible and get a more detailed stack trace.
     - Check application configuration: Environment variables, database credentials, cache settings. A common Symfony 500 is a misconfigured database connection.
---
**Confirming and Fixing the Root Cause**
1. Confirmation:
   - Reproducibility: Can you consistently reproduce the 500 error after identifying a potential cause?
   - Log Correlation: Do the specific error messages in Loki directly point to the suspected cause (e.g., "SQLSTATE[HY000]: General error: 1045 Access denied" confirms a DB credential issue)?
   - Metric Changes: Does a change in a specific metric (e.g., database connection pool exhaustion, memory usage) align with the incident start?
   - Minimal Change Test: If unsure, try a minimal, reversible change (e.g., temporarily increase CPU limit) and observe if the 500s subside.
2. Fixing the Root Cause:
   - The fix depends entirely on the identified root cause:
     - Application Code Bug:
       - Fix: Develop a code fix, deploy a new version via Helm.
       - Immediate Mitigation: Rollback to the last known good Helm release (helm rollback <release-name> <revision>).
     - Configuration Error (e.g., wrong DB credentials, missing env var):
       - Fix: Update Kubernetes Secrets or ConfigMaps, then trigger a rolling update of the Deployment (e.g., by changing a label or kubectl rollout restart deployment).
       - Immediate Mitigation: Rollback Helm release.
     - Resource Exhaustion (CPU, Memory):
       - Fix: Adjust resources.requests and resources.limits in the Helm chart/Terraform module. Consider Horizontal Pod Autoscaler (HPA) if load is variable.
       - Immediate Mitigation: Manually scale up replicas (kubectl scale deployment <app-name> --replicas=<N>).
     - Dependency Failure (Database, Cache, External API):
       - Fix: Address the issue with the dependency itself.
       - Immediate Mitigation: If the dependency is critical and failing, the API might need to be temporarily disabled or put into maintenance mode until the dependency is restored.
     - Network Policy Issue:
       - Fix: Update the Kubernetes Network Policy to allow necessary traffic.
     - Ingress/Service Misconfiguration:
       - Fix: Update Ingress/Service YAML or Helm chart values.
---
**Proposing Improvements to Prevent Similar Issues in the Future**
> Prevention is key to building resilient systems.<br/>
1. Enhanced Monitoring & Alerting:
   - Granular 5xx Alerts: Configure Prometheus alerts for specific 5xx error rates (e.g., 500s from a particular endpoint, not just overall).
   - Dependency Health Checks: Add Prometheus exporters or custom metrics to monitor the health and latency of critical external dependencies (DB, Redis, external APIs) from the application's perspective.
   - Resource Saturation Alerts: Alerts for CPU throttling, memory usage approaching limits, and disk space.
   - Pod Restart Alerts: Alert on excessive pod restarts or CrashLoopBackOff states.
   - APM Integration: Leverage AppDynamics/DataDog/LGTM's distributed tracing to quickly pinpoint bottlenecks and errors across microservices.
2. Robust Logging:
   - Structured Logging: Ensure Symfony logs are in a structured format (JSON) for easier parsing and querying in Loki.
   - Contextual Logging: Include request IDs, user IDs, and other relevant context in logs to trace specific user requests through the system.
   - Appropriate Log Levels: Use CRITICAL, ERROR, WARNING appropriately to distinguish severity.
   - Comprehensive Health Checks (Liveness & Readiness Probes):
   - Liveness Probe: More sophisticated checks that verify not just PHP-FPM is running, but also that it can connect to critical dependencies (e.g., database, Redis). If this fails, Kubernetes restarts the pod.
   - Readiness Probe: Check if the application is ready to serve traffic (e.g., database migrations complete, cache warmed up). If this fails, Kubernetes stops sending traffic to the pod until it's ready. This prevents 500s during startup.
3. Resource Management:
   - Accurate Requests & Limits: Continuously tune CPU and memory requests/limits based on observed usage patterns to prevent resource exhaustion.
   - Horizontal Pod Autoscaler (HPA): Implement HPA based on CPU/Memory utilization or custom metrics (e.g., requests per second) to automatically scale the number of replicas based on load.
4. Improved Deployment Strategies:
   - Canary Deployments: Gradually roll out new versions to a small subset of users/traffic first, monitoring for errors before a full rollout. Tools like Argo Rollouts can facilitate this.
   - Blue/Green Deployments: Deploy a new version alongside the old, then switch traffic instantly. Provides quick rollback.
5. Automated Rollbacks:
   - Integrate automated rollback mechanisms into the CI/CD pipeline based on alert thresholds (e.g., if 5xx errors spike after a deployment, automatically trigger a rollback to the previous version).
6. Configuration Management & Validation:
   - GitOps (ArgoCD): Use Git as the single source of truth for your Kubernetes configurations. ArgoCD automatically syncs cluster state with Git, providing clear history and auditability.
   - Pre-deployment Validation: Add steps in the CI pipeline to validate Helm chart values and Kubernetes manifests before deployment.
7. Chaos Engineering & Load Testing:
   - Proactive Testing: Regularly perform load tests to identify bottlenecks and breaking points under stress.
   - Chaos Engineering: Introduce controlled failures (e.g., network latency, pod termination) in non-production environments to test the system's resilience and verify monitoring/alerting.
8. Post-Mortem Culture:
   - Conduct thorough post-mortems for every major incident. Focus on "what happened," "why," and "what can we do to prevent recurrence," fostering a culture of continuous learning.
