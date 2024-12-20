terraform {
  cloud {
    organization = "mdna"
    workspaces {
      name = "hcp-tf-gcp"
    }
  }

  required_providers {
    tfe = {
      source = "hashicorp/tfe"
      version = "0.60.1"
    }
  }
}

provider "tfe" {
  # Configuration options
}

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
    "iam.googleapis.com",
    # "run.googleapis.com",
    # "sqladmin.googleapis.com",
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
    "google.subject"                        = "assertion.sub",
    "attribute.aud"                         = "assertion.aud",
    "attribute.terraform_run_phase"         = "assertion.terraform_run_phase",
    "attribute.terraform_project_id"        = "assertion.terraform_project_id",
    "attribute.terraform_project_name"      = "assertion.terraform_project_name",
    "attribute.terraform_workspace_id"      = "assertion.terraform_workspace_id",
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name",
    "attribute.terraform_organization_id"   = "assertion.terraform_organization_id",
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name",
    "attribute.terraform_run_id"            = "assertion.terraform_run_id",
    "attribute.terraform_full_workspace"    = "assertion.terraform_full_workspace",
  }
  oidc {
    issuer_uri = "https://app.terraform.io"
  }
}

# example service account that HCP Terraform will impersonate
resource "google_service_account" "hcp_tf" {
  account_id   = "hcp-tf"
  display_name = "Service Account for HCP Terraform Dynamic Credentials"
  # project      = data.google_project.project.id
}
 
# IAM verifies the HCP Terraform Workspace ID before authorizing access to impersonate the 'example' service account
resource "google_service_account_iam_member" "hcp_workload_identity_user" {
  service_account_id = google_service_account.hcp_tf.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.hcp_tf.name}/attribute.terraform_workspace_id/ws-brS5FKfw1L5RF1dq"
}

# create a variable set to store the workload identity federation config for the 'example' service account
resource "tfe_variable_set" "wip_variable_set" {
  name         = google_service_account.hcp_tf.account_id
  description  = "Workload identity federation configuration for ${google_service_account.hcp_tf.name}"
  organization = local.organization_name
}
 
# # share the variable set with another HCP Terraform Workspace
# resource "tfe_workspace_variable_set" "example" {
#   variable_set_id = tfe_variable_set.example.id
#   workspace_id    = "ws-XXXXXXXXXXXXXXX"
# }

resource "tfe_variable" "hcp_tf_provider_auth" {
  key             = "TFC_GCP_PROVIDER_AUTH"
  value           = "true"
  category        = "env"
  variable_set_id = tfe_variable_set.wip_variable_set.id
}
 
resource "tfe_variable" "hcp_tf_service_account_email" {
  sensitive       = true
  key             = "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL"
  value           = google_service_account.hcp_tf.email
  category        = "env"
  variable_set_id = tfe_variable_set.wip_variable_set.id
}
 
resource "tfe_variable" "hcp_tf_provider_name" {
  sensitive       = true
  key             = "TFC_GCP_WORKLOAD_PROVIDER_NAME"
  value           = google_iam_workload_identity_pool_provider.hcp_tf.name
  category        = "env"
  variable_set_id = tfe_variable_set.wip_variable_set.id
}

# share the variable set with another HCP Terraform Workspace
resource "tfe_workspace_variable_set" "wip_workspace_variable_set" {
  variable_set_id = tfe_variable_set.wip_variable_set.id
  workspace_id    = "ws-brS5FKfw1L5RF1dq"
}

resource "google_project_iam_member" "wip_admin" {
  member  = "serviceAccount:${google_service_account.hcp_tf.email}"
  role    = "roles/iam.workloadIdentityPoolAdmin"
  project = data.google_project.project.id
}

resource "google_project_iam_member" "owner" {
  member  = "serviceAccount:${google_service_account.hcp_tf.email}"
  role    = "roles/owner"
  project = data.google_project.project.id
}