
resource "google_compute_network" "pipeline_vpc" {
  name                    = "${local.name_prefix}-pipeline-vpc"
  auto_create_subnetworks = false
  description             = "VPC for the data processing pipeline"
}

resource "google_compute_subnetwork" "pipeline_subnet" {
  name          = "${local.name_prefix}-pipeline-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.pipeline_vpc.id

  private_ip_google_access = true # Allow access to GCP APIs without public IP

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}


resource "google_vpc_access_connector" "pipeline_connector" {
  name          = "${local.name_prefix}-connector"
  region        = var.region
  ip_cidr_range = var.connector_cidr
  network       = google_compute_network.pipeline_vpc.name

  min_instances = 2
  max_instances = 3
}


# Deny all ingress by default
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "${local.name_prefix}-deny-all-ingress"
  network = google_compute_network.pipeline_vpc.name

  direction = "INGRESS"
  priority  = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Allow internal traffic within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.pipeline_vpc.name

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/24", var.connector_cidr]
}


resource "google_compute_router" "pipeline_router" {
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.pipeline_vpc.id
}

resource "google_compute_router_nat" "pipeline_nat" {
  name   = "${local.name_prefix}-nat"
  router = google_compute_router.pipeline_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
