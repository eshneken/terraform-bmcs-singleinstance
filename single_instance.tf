#
# This is simple terraform template that consolidates everything to one file. 
# This will create a VCN, internet gateway, route table, security groups and start an instance. 
#
# When the instance is up it should be ping-able and ssh-accessible via the opc user 
#
#

variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key_path" {}
variable "compartment_ocid" {}
variable "ssh_public_key" {}

variable "region" {
  default = "us-ashburn-1"
}

### Provider

provider "oci" {
  tenancy_ocid         = "${var.tenancy_ocid}"
  user_ocid            = "${var.user_ocid}"
  fingerprint          = "${var.fingerprint}"
  private_key_path     = "${var.private_key_path}"
  region               = "${var.region}"
  disable_auto_retries = "true"
}

### Variables

variable "VPC-CIDR" {
  default = "10.0.0.0/16"
}

variable "InstanceImageOCID" {
  type = "map"

  default = {
    // Oracle-provided image "Oracle-Linux-7.4-2017.12.18-0"
    // See https://docs.us-phoenix-1.oraclecloud.com/Content/Resources/Assets/OracleProvidedImageOCIDs.pdf
    us-phoenix-1 = "ocid1.image.oc1.phx.aaaaaaaasc56hnpnx7swoyd2fw5gyvbn3kcdmqc2guiiuvnztl2erth62xnq"

    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaaxrqeombwty6jyqgk3fraczdd63bv66xgfsqka4ktr7c57awr3p5a"
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaayxmzu6n5hsntq4wlffpb4h6qh6z3uskpbm5v3v4egqlqvwicfbyq"
  }
}

data "oci_identity_availability_domains" "ADs" {
  compartment_id = "${var.tenancy_ocid}"
}

### Declare Network

resource "oci_core_virtual_network" "SingleInstanceVCN" {
  cidr_block     = "${var.VPC-CIDR}"
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceVCN"
}

resource "oci_core_internet_gateway" "SingleInstanceIGW" {
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceIGW"
  vcn_id         = "${oci_core_virtual_network.SingleInstanceVCN.id}"
}

resource "oci_core_route_table" "SingleInstanceRoutingTable" {
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${oci_core_virtual_network.SingleInstanceVCN.id}"
  display_name   = "SingleInstanceRoutingTable"

  route_rules {
    cidr_block        = "0.0.0.0/0"
    network_entity_id = "${oci_core_internet_gateway.SingleInstanceIGW.id}"
  }
}

resource "oci_core_security_list" "SingleInstanceSecList" {
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceSecList"
  vcn_id         = "${oci_core_virtual_network.SingleInstanceVCN.id}"

  egress_security_rules = [{
    protocol    = "6"
    destination = "0.0.0.0/0"
  },
    {
      protocol    = "1"
      destination = "0.0.0.0/0"
    },
  ]

  ingress_security_rules = [{
    tcp_options {
      "max" = 22
      "min" = 22
    }

    protocol = "6"
    source   = "0.0.0.0/0"
  },
    {
      icmp_options {
        "type" = 0
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
    {
      icmp_options {
        "type" = 3
        "code" = 4
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
    {
      icmp_options {
        "type" = 8
      }

      protocol = 1
      source   = "0.0.0.0/0"
    },
  ]
}

resource "oci_core_subnet" "SingleInstanceAD1" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  cidr_block          = "10.0.7.0/24"
  display_name        = "SingleInstanceAD1"
  compartment_id      = "${var.compartment_ocid}"
  vcn_id              = "${oci_core_virtual_network.SingleInstanceVCN.id}"
  route_table_id      = "${oci_core_route_table.SingleInstanceRoutingTable.id}"
  security_list_ids   = ["${oci_core_security_list.SingleInstanceSecList.id}"]
  dhcp_options_id     = "${oci_core_virtual_network.SingleInstanceVCN.default_dhcp_options_id}"
}

resource "oci_core_instance" "SingleInstance-Compute-1" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "SingleInstance-Compute-11"
  image               = "${var.InstanceImageOCID[var.region]}"
  shape               = "VM.Standard2.2"
  subnet_id           = "${oci_core_subnet.SingleInstanceAD1.id}"

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
  }
}


### Display Public IP of Instance

# Gets a list of vNIC attachments on the instance
data "oci_core_vnic_attachments" "InstanceVnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  instance_id         = "${oci_core_instance.SingleInstance-Compute-1.id}"
}

# Gets the OCID of the first (default) vNIC
data "oci_core_vnic" "InstanceVnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.InstanceVnics.vnic_attachments[0],"vnic_id")}"
}

output "public_ip" {
  value = "${data.oci_core_vnic.InstanceVnic.public_ip_address}"
}
