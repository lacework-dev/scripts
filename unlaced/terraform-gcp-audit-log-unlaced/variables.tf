variable "required_apis" {
  type = map(any)
  default = {
    iam             = "iam.googleapis.com"
    pubsub          = "pubsub.googleapis.com"
    serviceusage    = "serviceusage.googleapis.com"
    resourcemanager = "cloudresourcemanager.googleapis.com"
  }
}

variable "org_integration" {
  type        = bool
  default     = true
  description = "If set to true, configure an organization level integration"
}

variable "organization_id" {
  type        = string
  default     = ""
  description = "The organization ID, required if org_integration is set to true"
}

variable "project_id" {
  type        = string
  default     = ""
  description = "A project ID different from the default defined inside the provider"
  validation {
    condition     = can(regex("(^[a-z][a-z0-9-]{4,28}[a-z0-9]$|^$)", var.project_id))
    error_message = "The project_id variable must be a valid GCP project ID. It must be 6 to 30 lowercase ASCII letters, digits, or hyphens. It must start with a letter. Trailing hyphens are prohibited. Example: tokyo-rain-123."
  }
}

variable "use_existing_service_account" {
  type        = bool
  default     = false
  description = "Set this to true to use an existing Service Account"
}

variable "service_account_name" {
  type        = string
  default     = ""
  description = "The Service Account name (required when use_existing_service_account is set to true)"
}

variable "service_account_private_key" {
  type        = string
  default     = ""
  description = "The private key in JSON format, base64 encoded (required when use_existing_service_account is set to true)"
}

variable "existing_bucket_name" {
  type        = string
  default     = ""
  description = "The name of an existing bucket you want to send the logs to"
}

variable "custom_bucket_name" {
  type        = string
  default     = null
  description = "Override prefix based storage bucket name generation with custom name"
}

variable "bucket_force_destroy" {
  type        = bool
  default     = true
  description = "Force destroy bucket (if disabled, terraform will not be able do destroy non-empty bucket)"
}

variable "bucket_region" {
  type        = string
  default     = "US"
  description = "The region where the new bucket will be created, valid values for Multi-regions are (EU, US or ASIA) alternatively you can set a single region or Dual-regions follow the naming convention as outlined in the GCP bucket locations documentation https://cloud.google.com/storage/docs/locations#available-locations|string|US|false|"
}

variable "bucket_labels" {
  type        = map(string)
  default     = {}
  description = "Set of labels which will be added to the audit log bucket"
}

variable "existing_sink_name" {
  type        = string
  default     = ""
  description = "The name of an existing sink to be re-used for this integration"
}

variable "prefix" {
  type        = string
  default     = "lw-at"
  description = "The prefix that will be use at the beginning of every generated resource"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Set of labels which will be added to the resources managed by the module"
}

variable "lacework_integration_name" {
  type    = string
  default = "TF audit_log"
}

variable "wait_time" {
  type        = string
  default     = "10s"
  description = "Amount of time to wait before the next resource is provisioned."
}

variable "enable_ubla" {
  description = "Boolean for enabling Uniform Bucket Level Access on the audit log bucket.  Default is true"
  type        = bool
  default     = true
}

variable "lifecycle_rule_age" {
  description = "Number of days to keep audit logs in Lacework GCS bucket before deleting. Leave default to keep indefinitely"
  type        = number
  default     = -1
}

variable "pubsub_topic_labels" {
  type        = map(string)
  default     = {}
  description = "Set of labels which will be added to the topic"
}

variable "pubsub_subscription_labels" {
  type        = map(string)
  default     = {}
  description = "Set of labels which will be added to the subscription"
}

variable "k8s_filter" {
  type        = bool
  default     = true
  description = "Filter out GKE logs from GCP Audit Log sinks.  Default is true"
}

variable "google_workspace_filter" {
  type        = bool
  default     = true
  description = "Filter out Google Workspace login logs from GCP Audit Log sinks.  Default is true"
}

variable "custom_filter" {
  type        = string
  default     = ""
  description = "Customer defined Audit Log filter which will supersede all other filter options when defined"
}

variable "folders_to_exclude" {
  type        = list(string)
  default     = []
  description = "List of root folders to exclude in an organization-level integration.  Format is 'folders/1234567890'"
}

variable "include_root_projects" {
  type        = bool
  default     = true
  description = "Enables logic to include root-level projects if excluding folders.  Default is true"
}

variable "folders_to_include" {
  type        = set(string)
  default     = []
  description = "List of root folders to include in an organization-level integration.  Format is 'folders/1234567890'"
}

variable "create" {
  type        = bool
  default     = true
  description = "Set to false to prevent the module from creating any resources"
}
