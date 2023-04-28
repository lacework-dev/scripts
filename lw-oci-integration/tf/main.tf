terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
      version = "4.118.0"
    }
  }
}

##################################################
# PROVIDER CONFIG
##################################################

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

##################################################
# VARIABLES
##################################################

variable "tenancy_ocid" {
    type = string
    description = "oci tenancy id"
}
variable "region" {
    type = string
    description = "oci region"
}
variable "user_ocid" {
    type = string
    description = "oci user"
}
variable "fingerprint" {
    type = string
    description = "oci fingerprint"
}
variable "private_key_path" {
    type = string
    description = "oci private key path"
}
variable "group_name" {
    type = string
    description = "group name"
    default = "lacework_group_security_audit"
}

variable "user_name" {
    type = string
    description = "user name"
    default = "lacework_user_security_audit"
}

variable "policy_name" {
  type = string
  description = "policy name"
  default = "lacework_policy_security_audit"
}
##################################################
# OCI SETUP
##################################################

data "oci_identity_tenancy" "current" {
  tenancy_id = var.tenancy_ocid
}

locals {
    ssh_private_key_path = pathexpand("~/.oci/oci_api_key_lacework.pem")
    ssh_public_key_path = pathexpand("~/.oci/oci_api_key_lacework_public.pem")
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits = 2048
}

resource "local_file" "ssh-private-key" {
    content  = tls_private_key.ssh.private_key_pem
    filename = local.ssh_private_key_path
    file_permission = "0600"
}

resource "local_file" "ssh-public-key" {
    content  = tls_private_key.ssh.public_key_pem
    filename = local.ssh_public_key_path
    file_permission = "0600"
}

resource "oci_identity_user" "lacework_user_security_audit" {
  name        = var.user_name
  description = "A read only Lacework user to access resource configs."
  compartment_id = data.oci_identity_tenancy.current.id
  email       = "oci-audit@lacework.net"
}

resource "oci_identity_group" "lacework_group_security_audit" {
  name        = var.group_name
  description = "A lacework group needed to assign necessary read only permissions to lacework_user_security_audit."
  compartment_id = data.oci_identity_tenancy.current.id
}

resource "oci_identity_user_group_membership" "lacework_user_group_membership" {
  user_id  = oci_identity_user.lacework_user_security_audit.id
  group_id = oci_identity_group.lacework_group_security_audit.id
}

resource "oci_identity_policy" "lacework_policy_security_audit" {
  compartment_id = data.oci_identity_tenancy.current.id
  name        = var.policy_name
  description = "Policy that grants necessary permissions to perform the security audit."
  statements = [
    "Allow group '${var.group_name}' to inspect compartments in tenancy",
    "Allow group '${var.group_name}' to read audit-events in tenancy",
    "Allow group '${var.group_name}' to read buckets in tenancy",
    "Allow group '${var.group_name}' to read instance-family in tenancy",
    "Allow group '${var.group_name}' to read volume-family in tenancy",
    "Allow group '${var.group_name}' to read virtual-network-family in tenancy",
    "Allow group '${var.group_name}' to read users in tenancy",
    "Allow group '${var.group_name}' to read groups in tenancy",
    "Allow group '${var.group_name}' to read policies in tenancy",
    "Allow group '${var.group_name}' to read domains in tenancy",
    "Allow group '${var.group_name}' to inspect tag-defaults in tenancy"
  ]
}

resource "oci_identity_api_key" "lacework_user_api_key" {
  user_id = oci_identity_user.lacework_user_security_audit.id
  key_value = tls_private_key.ssh.public_key_pem
}

resource "local_file" "cloud_account" {
    content =   <<-EOT
                {
                    "name": "${data.oci_identity_tenancy.current.name}",
                    "type": "OciCfg",
                    "enabled": 1,
                    "data": {
                        "homeRegion": "${var.region}",
                        "tenantId": "${var.tenancy_ocid}",
                        "tenantName": "${data.oci_identity_tenancy.current.name}",
                        "userOcid": "${oci_identity_user.lacework_user_security_audit.id}",
                        "credentials": {
                            "fingerprint": "${oci_identity_api_key.lacework_user_api_key.fingerprint}",
                            "privateKey": "${replace(chomp(tls_private_key.ssh.private_key_pem_pkcs8), "\n", "\\n")}"
                        }
                    }
                }
                EOT
    filename = pathexpand("~/.oci/lacework_cloud_account.json")
    file_permission = "0600"
}

##################################################
# OUTPUT
##################################################

locals {
    nextstep =  <<-EOT
                Run the following lacework-cli command to complete the integration:
                -------------------------------------------------------------------
                lacework api post /api/v2/CloudAccounts -d "$(cat ${pathexpand("~/.oci/lacework_cloud_account.json")})"

                Note: add --profile=<YOUR PROFILE> as required
                EOT
}
output "nextstep" {
    value = local.nextstep
}

