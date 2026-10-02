# Nomad job for the containerized NGINX app.
# Run with:  nomad job run -var="image_tag=latest" nomad/nginx-app.nomad.hcl

variable "image_tag" {
  type        = string
  description = "Image tag to deploy from GHCR (commit SHA or 'latest')."
  default     = "latest"
}

job "nginx-app" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 1

    # Keep serving in-flight requests while Consul deregisters the service.
    shutdown_delay = "5s"

    # Nomad picks a free host port and exposes it as NOMAD_PORT_http.
    network {
      port "http" {
        to = 8080
      }
    }

    # Register with Consul and health-check the app over HTTP.
    service {
      name     = "nginx-app"
      port     = "http"
      provider = "consul"

      check {
        type     = "http"
        path     = "/healthz"
        interval = "10s"
        timeout  = "2s"
      }
    }

    # Restart a task that keeps failing inside the same allocation.
    restart {
      attempts = 2
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    # If the allocation cannot be made healthy here, move it elsewhere.
    reschedule {
      attempts       = 3
      interval       = "1h"
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "5m"
      unlimited      = false
    }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "2m"
      auto_revert      = true
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "ghcr.io/neelstar8/devops-intern-final:${var.image_tag}"
        ports = ["http"]
      }

      resources {
        cpu    = 100 # MHz
        memory = 64  # MB
      }
    }
  }
}
