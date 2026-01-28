############################################
# Networking for Example 3 topology:
# - Public API subnet
# - Private worker + pods subnets (via NAT/Service GW)
# - Public LB subnet
############################################

locals {
  subnets = {
    k8s_api = {
      cidr_block = "10.0.0.0/29"
    },
    k8s_worker_nodes = {
      cidr_block = "10.0.1.0/24"
    },
    k8s_pods = {
      cidr_block = "10.0.32.0/19"
    },
    k8s_loadbalancers = {
      cidr_block = "10.0.2.0/24"
    }
  }

  lowercase_region_identifier = lower(var.region_identifier)
  uppercase_region_identifier = upper(var.region_identifier)

  # Cloudflare-only inbound allowed ranges for LB subnet
  cloudflare_ipv4_cidrs = ["173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22"]
}

data "oci_core_services" "this" {
  filter {
    name   = "name"
    values = ["All ${local.uppercase_region_identifier} Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_virtual_network" "k8s_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "k8sVCN"
  dns_label      = "k8svcn"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  display_name   = "internet-gateway-0"
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "nat-gateway-0"
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "service-gateway-0"

  services {
    service_id = data.oci_core_services.this.services[0]["id"]
  }
}

# --- Public API subnet ---
resource "oci_core_subnet" "k8s_api" {
  cidr_block        = local.subnets.k8s_api.cidr_block
  display_name      = "KubernetesAPIendpoint"
  dns_label         = "kubernetesapi"
  security_list_ids = [oci_core_security_list.k8s_api.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.k8s_vcn.id
  route_table_id    = oci_core_route_table.k8s_api.id
  dhcp_options_id   = oci_core_virtual_network.k8s_vcn.default_dhcp_options_id
}

resource "oci_core_route_table" "k8s_api" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "routetable-KubernetesAPIendpoint"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "k8s_api" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "seclist-KubernetesAPIendpoint"

  # Egress to workers/pods + OCI services
  egress_security_rules {
    protocol    = "6"
    destination = local.subnets.k8s_worker_nodes.cidr_block

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  egress_security_rules {
    protocol    = "1"
    destination = local.subnets.k8s_worker_nodes.cidr_block

    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.subnets.k8s_pods.cidr_block
  }

  egress_security_rules {
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"
  }

  egress_security_rules {
    protocol         = "1"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Ingress from workers/pods + 6443 public
  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_worker_nodes.cidr_block

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_worker_nodes.cidr_block

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = local.subnets.k8s_worker_nodes.cidr_block

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_pods.cidr_block

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_pods.cidr_block

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

# --- Private worker subnet ---
resource "oci_core_subnet" "k8s_worker_nodes" {
  cidr_block                = local.subnets.k8s_worker_nodes.cidr_block
  display_name              = "workernodes"
  dns_label                 = "workernodes"
  security_list_ids         = [oci_core_security_list.k8s_worker_nodes.id]
  compartment_id            = var.compartment_ocid
  vcn_id                    = oci_core_virtual_network.k8s_vcn.id
  route_table_id            = oci_core_route_table.k8s_worker_nodes.id
  dhcp_options_id           = oci_core_virtual_network.k8s_vcn.default_dhcp_options_id
  prohibit_internet_ingress = true
}

resource "oci_core_route_table" "k8s_worker_nodes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "routetable-workernodes"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination_type  = "SERVICE_CIDR_BLOCK"
    destination       = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

resource "oci_core_security_list" "k8s_worker_nodes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "seclist-workernodes"

  egress_security_rules {
    protocol    = "6"
    destination = local.subnets.k8s_api.cidr_block

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  egress_security_rules {
    protocol    = "6"
    destination = local.subnets.k8s_api.cidr_block

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.subnets.k8s_pods.cidr_block
  }

  egress_security_rules {
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"
  }

  egress_security_rules {
    protocol         = "1"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_pods.cidr_block

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = local.subnets.k8s_api.cidr_block

    tcp_options {
      min = 10250
      max = 10250
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "all"
    source   = local.subnets.k8s_loadbalancers.cidr_block
  }
}

# --- Private pods subnet ---
resource "oci_core_subnet" "k8s_pods" {
  cidr_block                = local.subnets.k8s_pods.cidr_block
  display_name              = "pods"
  dns_label                 = "pods"
  security_list_ids         = [oci_core_security_list.k8s_pods.id]
  compartment_id            = var.compartment_ocid
  vcn_id                    = oci_core_virtual_network.k8s_vcn.id
  route_table_id            = oci_core_route_table.k8s_pods.id
  dhcp_options_id           = oci_core_virtual_network.k8s_vcn.default_dhcp_options_id
  prohibit_internet_ingress = true
}

resource "oci_core_route_table" "k8s_pods" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "routetable-pods"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination_type  = "SERVICE_CIDR_BLOCK"
    destination       = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

resource "oci_core_security_list" "k8s_pods" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "seclist-pods"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  egress_security_rules {
    protocol    = "6"
    destination = local.subnets.k8s_api.cidr_block

    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    protocol    = "6"
    destination = local.subnets.k8s_api.cidr_block

    tcp_options {
      min = 12250
      max = 12250
    }
  }

  egress_security_rules {
    protocol    = "1"
    destination = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = local.subnets.k8s_pods.cidr_block
  }

  egress_security_rules {
    protocol         = "6"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"
  }

  egress_security_rules {
    protocol         = "1"
    destination_type = "SERVICE_CIDR_BLOCK"
    destination      = "all-${local.lowercase_region_identifier}-services-in-oracle-services-network"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "all"
    source   = local.subnets.k8s_worker_nodes.cidr_block
  }

  ingress_security_rules {
    protocol = "all"
    source   = local.subnets.k8s_pods.cidr_block
  }

  ingress_security_rules {
    protocol = "all"
    source   = local.subnets.k8s_api.cidr_block
  }
}

# --- Public Load Balancer subnet ---
resource "oci_core_subnet" "k8s_loadbalancers" {
  cidr_block        = local.subnets.k8s_loadbalancers.cidr_block
  display_name      = "loadbalancers"
  dns_label         = "loadbalancers"
  security_list_ids = [oci_core_security_list.k8s_loadbalancers.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.k8s_vcn.id
  route_table_id    = oci_core_route_table.k8s_loadbalancers.id
  dhcp_options_id   = oci_core_virtual_network.k8s_vcn.default_dhcp_options_id
}

resource "oci_core_route_table" "k8s_loadbalancers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "routetable-serviceloadbalancers"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "k8s_loadbalancers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.k8s_vcn.id
  display_name   = "seclist-loadbalancers"

  # Allow LB → worker nodes
  egress_security_rules {
    protocol    = "all"
    destination = local.subnets.k8s_worker_nodes.cidr_block
  }

  ###########################################################
  # 🚨 Cloudflare-only ingress to LB (80–443)
  # These are the real rules now active.
  ###########################################################
  dynamic "ingress_security_rules" {
    for_each = local.cloudflare_ipv4_cidrs
    content {
      protocol = "6"   # TCP
      source   = ingress_security_rules.value

      tcp_options {
        min = 80
        max = 443
      }
    }
  }

  ###########################################################
  # ⛔ OLD RULES — KEPT FOR REFERENCE BUT NOT ACTIVE
  # These used to allow the entire internet access.
  # Leaving them commented out for future debugging/comparison.
  ###########################################################
  # ingress_security_rules {
  #   protocol = "6"
  #   source   = "0.0.0.0/0"
  #   tcp_options {
  #     min = 443
  #     max = 443
  #   }
  # }
  #
  # ingress_security_rules {
  #   protocol = "6"
  #   source   = "0.0.0.0/0"
  #   tcp_options {
  #     min = 80
  #     max = 80
  #   }
  # }
}
