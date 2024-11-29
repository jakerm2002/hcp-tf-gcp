provider "google" {
  project     = "hcp-tf-gcp"
  region      = "us-central1"
}

locals {
  organization_name = "mdna"
}

variable "gcp_service_list" {
  description ="The list of apis necessary for the project"
  type = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "gcp_services" {
  for_each = toset(var.gcp_service_list)
  project = "hcp-tf-gcp"
  service = each.key
}

data "google_project" "project" {
}

# create a workload identity pool for HCP Terraform
resource "google_iam_workload_identity_pool" "hcp_tf" {
  project                   = data.google_project.project.number
  workload_identity_pool_id = "hcp-tf-pool"
  display_name              = "HCP Terraform Pool"
  description               = "Used to authenticate to Google Cloud"
}
 
# create a workload identity pool provider for HCP Terraform
resource "google_iam_workload_identity_pool_provider" "hcp_tf" {
  project                            = data.google_project.project.number
  workload_identity_pool_id          = google_iam_workload_identity_pool.hcp_tf.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-tf-provider"
  display_name                       = "HCP Terraform Provider"
  description                        = "Used to authenticate to Google Cloud"
  attribute_condition                = "assertion.terraform_organization_name==\"${local.organization_name}\""
  attribute_mapping = {
    "google.subject"                     = "assertion.sub"
    "attribute.terraform_workspace_id"   = "assertion.terraform_workspace_id"
    "attribute.terraform_full_workspace" = "assertion.terraform_full_workspace"
  }
  oidc {
    issuer_uri = "https://app.terraform.io"
  }
}