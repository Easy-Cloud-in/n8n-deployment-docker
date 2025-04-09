# Prometheus Monitoring for n8n

This document explains how Prometheus monitoring works with n8n and how to set it up.

## What is Prometheus?

Prometheus is an open-source monitoring and alerting toolkit designed for reliability and scalability. It's particularly well-suited for monitoring containerized environments like Docker.

## Why Monitor n8n?

Monitoring n8n with Prometheus provides several benefits:

1. **Performance Tracking**: Identify bottlenecks and optimize resource allocation
2. **Early Problem Detection**: Catch issues before they affect your workflows
3. **Resource Planning**: Understand usage patterns to plan for scaling
4. **Uptime Monitoring**: Ensure your automation platform is always available

## How Prometheus Works

Prometheus works on a pull model, where it scrapes metrics from your applications at regular intervals.

1. **Metrics Collection**

   - Prometheus collects time-series data from monitored targets
   - Common metrics include:
     - CPU usage
     - Memory consumption
     - Request counts
     - Response times
     - Custom application metrics

2. **Data Model**

   ```
   metric_name{label1="value1", label2="value2"} value
   ```

   Example:

   ```
   http_requests_total{method="POST", endpoint="/api/workflows"} 2345
   ```

## Basic Setup for n8n

To enable Prometheus monitoring for n8n:

1. Edit your docker-compose.yml file to include the Prometheus configuration:

   ```yaml
   n8n:
     image: n8nio/n8n
     environment:
       - N8N_METRICS=true
       - N8N_METRICS_PREFIX=n8n_
     ports:
       - '5678:5678'
       - '9100:9100' # Prometheus metrics port
   ```

2. Configure Prometheus to scrape metrics from n8n by adding this to your prometheus.yml:

   ```yaml
   scrape_configs:
     - job_name: 'n8n'
       static_configs:
         - targets: ['n8n:9100']
   ```

## Key Metrics to Monitor

1. **Workflow Execution Metrics**

   - `n8n_workflow_executions_total`: Total number of workflow executions
   - `n8n_workflow_execution_duration_seconds`: Duration of workflow executions

2. **Node Execution Metrics**

   - `n8n_node_executions_total`: Total number of node executions
   - `n8n_node_execution_duration_seconds`: Duration of node executions

3. **System Metrics**
   - `n8n_system_memory_usage_bytes`: Memory usage of n8n
   - `n8n_system_cpu_usage_percent`: CPU usage of n8n

## Setting Up Alerts

You can configure Prometheus alerts to notify you when certain conditions are met:

```yaml
groups:
  - name: n8n_alerts
    rules:
      - alert: HighWorkflowFailureRate
        expr: rate(n8n_workflow_executions_total{status="failed"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: 'High workflow failure rate'
          description: 'Workflow failure rate is above 10% for the last 5 minutes'
```

## Visualizing with Grafana

For better visualization, you can connect Prometheus to Grafana:

1. Add Prometheus as a data source in Grafana
2. Import or create dashboards to visualize n8n metrics
3. Set up Grafana alerts for additional notification options

## Troubleshooting

If you're not seeing metrics:

1. Verify that N8N_METRICS is set to true
2. Check that port 9100 is exposed and accessible
3. Confirm Prometheus is correctly configured to scrape n8n
4. Look for errors in the Prometheus logs
