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

### Provider

provider "baremetal" {
  tenancy_ocid     = "${var.tenancy_ocid}"
  user_ocid        = "${var.user_ocid}"
  fingerprint      = "${var.fingerprint}"
  private_key_path = "${var.private_key_path}"
}

### Variables

variable "VPC-CIDR" {
  default = "10.0.0.0/16"
}

variable "InstanceOS" {
    default = "Oracle Linux"
}

variable "InstanceOSVersion" {
    default = "7.3"
}

data "baremetal_identity_availability_domains" "ADs" {
  compartment_id = "${var.tenancy_ocid}"
}

# Gets the OCID of the OS image to use
data "baremetal_core_images" "OLImageOCID" {
    compartment_id = "${var.compartment_ocid}"
    operating_system = "${var.InstanceOS}"
    operating_system_version = "${var.InstanceOSVersion}"
}

### Declare Network

resource "baremetal_core_virtual_network" "SingleInstanceVCN" {
  cidr_block     = "${var.VPC-CIDR}"
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceVCN"
}

resource "baremetal_core_internet_gateway" "SingleInstanceIGW" {
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceIGW"
  vcn_id         = "${baremetal_core_virtual_network.SingleInstanceVCN.id}"
}

resource "baremetal_core_route_table" "SingleInstanceRoutingTable" {
  compartment_id = "${var.compartment_ocid}"
  vcn_id         = "${baremetal_core_virtual_network.SingleInstanceVCN.id}"
  display_name   = "SingleInstanceRoutingTable"

  route_rules {
    cidr_block        = "0.0.0.0/0"
    network_entity_id = "${baremetal_core_internet_gateway.SingleInstanceIGW.id}"
  }
}

resource "baremetal_core_security_list" "SingleInstanceSecList" {
  compartment_id = "${var.compartment_ocid}"
  display_name   = "SingleInstanceSecList"
  vcn_id         = "${baremetal_core_virtual_network.SingleInstanceVCN.id}"

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

resource "baremetal_core_subnet" "SingleInstanceAD1" {
  availability_domain = "${lookup(data.baremetal_identity_availability_domains.ADs.availability_domains[0],"name")}"
  cidr_block          = "10.0.7.0/24"
  display_name        = "SingleInstanceAD1"
  compartment_id      = "${var.compartment_ocid}"
  vcn_id              = "${baremetal_core_virtual_network.SingleInstanceVCN.id}"
  route_table_id      = "${baremetal_core_route_table.SingleInstanceRoutingTable.id}"
  security_list_ids   = ["${baremetal_core_security_list.SingleInstanceSecList.id}"]
}

resource "baremetal_core_instance" "SingleInstance-Compute-1" {
  availability_domain = "${lookup(data.baremetal_identity_availability_domains.ADs.availability_domains[0],"name")}" 
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "SingleInstance-Compute-1"
  image               = "${lookup(data.baremetal_core_images.OLImageOCID.images[0], "id")}"

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
  }
  shape     = "VM.Standard1.2"
  subnet_id = "${baremetal_core_subnet.SingleInstanceAD1.id}"
}

### Display Public IP of Instance

# Gets a list of vNIC attachments on the instance
data "baremetal_core_vnic_attachments" "InstanceVnics" { 
compartment_id = "${var.compartment_ocid}" 
availability_domain = "${lookup(data.baremetal_identity_availability_domains.ADs.availability_domains[0],"name")}" 
instance_id = "${baremetal_core_instance.SingleInstance-Compute-1.id}" 
} 

# Gets the OCID of the first (default) vNIC
data "baremetal_core_vnic" "InstanceVnic" { 
vnic_id = "${lookup(data.baremetal_core_vnic_attachments.InstanceVnics.vnic_attachments[0],"vnic_id")}" 
}

output "public_ip" {
value = "${data.baremetal_core_vnic.InstanceVnic.public_ip_address}"
}

