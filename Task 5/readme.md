# Monitoring and Alerting Review for Symfony PHP Application
- Current Setup:
  - Prometheus + Alertmanager
  - Grafana dashboards (mostly system-level)
  - Loki for logs
- Goals: Propose application-level metrics, collection methods, key alerts, dashboard structure, and health definition.
---
1. Proposed Application-Level Metrics to Collect
   - Beyond basic system metrics (CPU, memory, network), these application-specific metrics provide deep insight into your Symfony API's behavior and health:
   - **HTTP Request Metrics (via Nginx/PHP-FPM or Symfony Bundle)**:
     - `http_requests_total`: Total number of requests, broken down by status code (2xx, 3xx, 4xx, 5xx), HTTP method, and endpoint path.
     - `http_request_duration_seconds`: Histogram of request processing times, broken down by endpoint.
     - `http_request_size_bytes`: Size of incoming requests.
     - `http_response_size_bytes`: Size of outgoing responses.
   - **PHP-FPM Pool Metrics**:
     - `php_fpm_active_processes`: Number of active PHP-FPM processes.
     - `php_fpm_idle_processes`: Number of idle PHP-FPM processes.
     - `php_fpm_listen_queue_length`: Number of requests in the listen queue (waiting for a process).
     - `php_fpm_max_children_reached_total`: Total times pm.max_children has been reached.
     - `php_fpm_slow_requests_total`: Total number of slow requests.
   - **Symfony Application Metrics (Custom/Internal)**:
     - Database Interactions:
       - `db_queries_total`: Total database queries, by type (SELECT, INSERT, UPDATE, DELETE) and table/entity.
       - `db_query_duration_seconds`: Histogram of database query execution times.
       - `db_connection_pool_usage`: Current number of active/idle database connections.
     - Cache Usage:
       - `cache_hits_total, cache_misses_total`: For Redis or other caching layers.
       - `cache_read_duration_seconds`, `cache_write_duration_seconds`.
     - Message Queue (Pub/Sub) Metrics:
       - `pubsub_messages_published_total`: Number of messages published to topics.
       - `pubsub_messages_consumed_total`: Number of messages consumed from subscriptions.
       - `pubsub_message_processing_duration_seconds`: Time taken to process a message.
       - `pubsub_failed_messages_total`: Number of messages that failed processing.
     - External API Calls:
       - `external_api_calls_total`: Total calls to external services, by service name and status.
       - `external_api_call_duration_seconds`: Latency of calls to external services.
     - Business Logic Metrics (Crucial for understanding application health):
       - `user_registrations_total`, `order_creations_total`, `payment_failures_total`, etc. (specific to your API's domain). These directly reflect business performance.
     - Error/Exception Metrics:
       - `application_exceptions_total`: Total exceptions caught/uncaught, broken down by exception type or code location.
       - `application_log_errors_total`: Count of ERROR or CRITICAL level logs.
2. How to Collect Application-Level Metrics
   - `PHP-FPM Exporter`:
     - **Method**: Deploy a php-fpm-exporter (e.g., https://github.com/hipages/php-fpm_exporter) as a sidecar container alongside your PHP-FPM application pod, or as a separate daemonset/deployment if you have multiple PHP-FPM instances per node.
     - **Mechanism**: It scrapes the PHP-FPM status page (/status or /ping) and exposes these metrics in Prometheus format.
   - `Symfony Prometheus Bundle / Custom Metrics`:
     - **Method**: Integrate a Prometheus client library or bundle directly into your Symfony application. A popular choice is php-prometheus/prometheus_client_php or a Symfony-specific bundle if available.
     - **Mechanism**:
       - `Middleware/Event Listeners`: Use Symfony event listeners (e.g., for kernel.request, kernel.response, kernel.exception) to increment counters, observe histograms for HTTP requests.
       - `Dependency Injection`: Inject the Prometheus client into your services to instrument database queries, cache operations, Pub/Sub interactions, and custom business logic.
       - `Exposition`: The bundle typically exposes a /metrics endpoint on your application's web server (e.g., Nginx serving your Symfony app), which Prometheus scrapes.
   - `Log Parsing (Loki + Promtail + LogQL)`:
     - **Method**: While not directly Prometheus metrics, Loki allows you to derive metrics from logs using LogQL's rate() and count_over_time() functions.
     - **Mechanism**: Promtail collects logs from your PHP-FPM containers and sends them to Loki. You can then write Grafana panels using LogQL queries to show, for example, the rate(count_over_time({job="symfony-api"} |= "ERROR" [5m])) to get error rates from logs. This is useful for errors not caught by explicit metrics.
   - `Blackbox Exporter`:
     - **Method**: Deploy the Prometheus Blackbox Exporter within your cluster.
     - **Mechanism**: Use it to perform external HTTP checks against your Ingress endpoint. This verifies external reachability and HTTP status codes from an outside perspective, complementing internal application metrics.
4. Key Alerts to Define
   - Alerts should follow the "Golden Signals" (Latency, Traffic, Errors, Saturation) and critical application-specific issues.
   - High Error Rate (Application-Level):
   - ```sh
       ALERT High5xxErrorRate
       IF sum(rate(http_requests_total{job="symfony-api", status_code=~"5.."}[5m])) by (endpoint) / sum(rate(http_requests_total{job="symfony-api"}[5m])) by (endpoint) > 0.05
       FOR 5m
       LABELS { severity = "critical" }
       ANNOTATIONS { summary = "High 5xx error rate on {{ $labels.endpoint }}", description = "More than 5% of requests to {{ $labels.endpoint }} are returning 5xx errors for 5 minutes." }
      ```
   - High Latency:
   - ```sh
     ALERT HighRequestLatency
     IF histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="symfony-api"}[5m])) by (le, endpoint)) > 1 (P95 latency over 1 second)
     FOR 5m
     LABELS { severity = "warning" }
     ANNOTATIONS { summary = "High request latency on {{ $labels.endpoint }}", description = "P95 request latency for {{ $labels.endpoint }} is over 1 second for 5 minutes." }
     ```
   - Low Throughput/Traffic Drop:
   - ```sh
     ALERT LowTraffic
     IF sum(rate(http_requests_total{job="symfony-api", status_code=~"2.."}[5m])) by (endpoint) < 5 (Less than 5 successful requests per second)
     FOR 10m
     LABELS { severity = "warning" }
     ANNOTATIONS { summary = "Low traffic on {{ $labels.endpoint }}", description = "Successful request rate for {{ $labels.endpoint }} has dropped significantly." }
   - PHP-FPM Queue Full / Max Children Reached:
   - ```sh
     ALERT PhpFpmQueueFull
     IF php_fpm_listen_queue_length{job="php-fpm-exporter"} > 0
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS { summary = "PHP-FPM listen queue is not empty", description = "PHP-FPM processes are saturated and requests are queuing up." }
   - ALERT Php Fpm Max Children Reached:
   - ```sh
     IF increase(php_fpm_max_children_reached_total[5m]) > 0
     FOR 1m
     LABELS { severity = "warning" }
     ANNOTATIONS { summary = "PHP-FPM max children reached", description = "PHP-FPM hit its maximum process limit, potentially causing dropped requests." }
     ```
   - Pod CrashLoopBackOff / OOMKilled:
   - ```sh
     ALERT KubernetesPodCrashLoopBackOff
     IF kube_pod_container_status_restarts_total{namespace="<your-namespace>", container=~"php-fpm|nginx"} > 0 (or kube_pod_container_status_last_terminated_reason{reason="OOMKilled"})
     FOR 5m
     LABELS { severity = "critical" }
     ANNOTATIONS { summary = "Pod {{ $labels.pod }} in CrashLoopBackOff", description = "Container {{ $labels.container }} in pod {{ $labels.pod }} is repeatedly crashing." }
     ```
   - Dependency Failure (e.g., Database/Redis):
   - ```sh
     ALERT DatabaseConnectionFailure
     IF sum(rate(db_connection_errors_total{job="symfony-api"}[5m])) by (instance) > 0
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS { summary = "Database connection errors", description = "Symfony API is failing to connect to the database." }
   - Critical Log Messages (Loki-derived):
   - ```sh
     ALERT CriticalLogMessages
     IF sum(rate(log_messages_total{job="symfony-api", level="CRITICAL"}[1m])) by (container) > 0
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS { summary = "Critical log message detected", description = "A critical log message has appeared in {{ $labels.container }} logs." }
4. Structuring an Effective Grafana Dashboard
  - An effective Grafana dashboard tells a story, moving from high-level health to detailed insights.
  - Dashboard Structure:
  1. **Overview / Golden Signals (Top Row)**:
     - *Panels*:
       - Request Rate (Traffic): Total HTTP requests per second (sum of 2xx, 3xx, 4xx, 5xx).
       - Error Rate (Errors): Percentage of 5xx errors.
       - Latency (P95/P99): Histogram quantile for request duration.
       - Active PHP-FPM Processes (Saturation): Current active processes vs. max children.
     - *Purpose*: Quick glance at overall system health. If any of these are red, you know there's a problem.
  2. **HTTP Request Details**:
     - *Panels*:
       - HTTP Status Code Breakdown: Stacked graph of 2xx, 3xx, 4xx, 5xx requests over time.
       - Latency by Endpoint (Heatmap/Graph): P95/P99 latency for top N endpoints.
       - Requests by Endpoint (Graph): Traffic distribution across API endpoints.
     - *Purpose*: Identify problematic endpoints, understand traffic patterns.
  3. **PHP-FPM Performance**:
     - *Panels*:
       - PHP-FPM Process Pool: Graph showing active, idle, and total processes.
       - Listen Queue Length: Graph showing requests waiting in queue.
       - Slow Requests: Graph showing php_fpm_slow_requests_total.
       - Max Children Reached: Graph showing php_fpm_max_children_reached_total.
     - *Purpose*: Diagnose PHP-FPM saturation, identify bottlenecks in process management.
  4. **Resource Utilization (Kubernetes Pods)**:
     - *Panels*:
       - CPU Usage: CPU usage of PHP-FPM pods (absolute and percentage of requests/limits).
       - Memory Usage: Memory usage of PHP-FPM pods (absolute and percentage of requests/limits).
       - Network I/O: Ingress/Egress bytes for pods.
       - Pod Restarts: Count of pod restarts over time.
     - *Purpose*: Identify resource constraints, OOMKills, or unstable pods.
  5. **Dependency Health**:
     - *Panels*:
       - AlloyDB/Database Metrics: Connection pool usage, query latency, active queries, errors.
       - Redis Metrics: Cache hit/miss ratio, memory usage, latency.
       - Pub/Sub Metrics: Message backlog, publish/consume rates, processing latency.
       - External API Latency/Errors: As collected by your Symfony app.
     - *Purpose*: Pinpoint if an external dependency is the root cause of application issues.
  6. **Logs (Loki Integration)**:
     - *Panels*:
       - Error Log Stream: A Loki panel showing ERROR and CRITICAL level logs for the Symfony API.
       - General Log Stream: A Loki panel showing all logs for the Symfony API, allowing for quick filtering.
     - *Purpose*: Directly view application logs alongside metrics, crucial for debugging.

**Key Dashboard Features**:
- *Templating Variables: Use variables for namespace, deployment, pod, container to quickly filter the dashboard to specific instances.*
- *Time Range Selector: Standard Grafana feature for selecting the period to view.*
- *Annotations: Display deployment markers or other significant events on graphs to correlate changes with metric behavior.*

5. Defining and Monitoring Application Health
  - Defining application health goes beyond just "is it running?" It encompasses performance, functionality, and user experience.
  1. Synthetics / Blackbox Monitoring:
     - Definition: An external system (e.g., UptimeRobot, Google Cloud Monitoring Synthetics, or a dedicated Blackbox Exporter instance) regularly makes actual HTTP requests to your API's public Ingress endpoint.
     - Monitoring: Checks for expected HTTP status codes (200 OK), response times, and potentially specific content in the response body. This is the "user's eye view" of health.
     - Alerting: Immediate alerts if the endpoint is unreachable or returns unexpected status codes/content.
  2. Liveness and Readiness Probes (Kubernetes Native):
     - Definition:
       - Liveness Probe: Determines if a container is still running and healthy enough to continue serving. If it fails, Kubernetes restarts the container. For PHP-FPM, this might be a simple check that PHP-FPM process is alive, or a more advanced one that verifies database connectivity.
       - Readiness Probe: Determines if a container is ready to accept traffic. If it fails, Kubernetes removes the pod from the Service endpoints. This is crucial during startup (e.g., waiting for database migrations to complete) or during temporary outages of critical dependencies.
     - Monitoring: kubectl get events, kubectl describe pod, and Grafana panels showing pod restart counts or readiness probe failures.
  3. Golden Signals (SLIs/SLOs):
     - Definition:
       - Latency: The time it takes to serve a request. Define an SLO (Service Level Objective) like "95% of requests must be served in under 500ms."
       - Traffic: The rate of requests to your service.
       - Errors: The rate of failed requests (e.g., 5xx HTTP responses, application exceptions). Define an SLO like "Error rate must not exceed 0.1%."
       - Saturation: How busy your service is (e.g., CPU utilization, memory usage, PHP-FPM queue length). Define an SLO like "PHP-FPM listen queue must be empty 99% of the time."
     - Monitoring: Dedicated Grafana panels for each of these, with visual thresholds indicating SLO breaches. Prometheus alerts configured to fire when SLOs are violated.
  4. Dependency Health:
     - Definition: All critical external services (AlloyDB, Redis, Pub/Sub) are reachable, responsive, and operating within their defined performance parameters.
     - Monitoring: Dedicated sections in Grafana dashboards for each dependency, showing their key metrics (latency, error rates, resource usage). Alerts for connectivity issues or performance degradation.
  5. Business Metrics:
     - Definition: Key business processes are completing successfully and at expected rates (e.g., "number of successful user sign-ups per hour," "number of completed orders").
     - Monitoring: Custom metrics collected from your application and displayed in Grafana. Alerts if these rates drop unexpectedly or if failure rates increase.
---
**By combining these aspects, you create a holistic view of application health, allowing you to quickly detect, diagnose, and respond to issues, ensuring a reliable and performant Symfony API.**