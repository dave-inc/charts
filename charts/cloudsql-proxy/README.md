# CloudSQL Proxy v2 Helm Chart

## Description

This Helm chart deploys a CloudSQL Proxy v2 instance in Kubernetes, facilitating connections to Google Cloud SQL databases. It's designed to provide an alternative to the sidecar pattern, allowing internal Kubernetes service name-based connections when TCP connections are required.

## Purpose

The main purpose of this chart is to:

1. Deploy Cloud SQL Proxy v2 as a standalone service in Kubernetes.
2. Enable TCP connections to Cloud SQL databases using internal Kubernetes service names.
3. Provide a flexible and scalable solution for applications requiring database access without using the sidecar pattern with socket paths.

## Features

- Kyverno compliant, meeting policy requirements for resource requests and probes (includes startup, liveness, and readiness probes)
- Supports multiple replica deployments
- Configurable security contexts and resource limits
- Built-in liveness, readiness, and startup probes
- Support for custom annotations and labels
- Flexible volume mounting for secrets and configmaps
- Integration with Datadog for monitoring and APM (optional)
- Topology spread constraints for high availability deployments

## Prerequisites

- Kubernetes
- Helm 
- Google Cloud Platform account with Cloud SQL instance(s)

## Notes

- Ensure that the necessary GCP credentials are properly configured and accessible to the pods.
- This chart is designed for Cloud SQL Proxy v2. Make sure you're using a compatible version of the proxy image.
- For production use, always review and adjust the security settings as per your organization's requirements.
