locals {
  resource_level = var.org_integration ? "ORGANIZATION" : "PROJECT"
  #resource_id    = var.org_integration ? var.organization_id : module.lacework_at_svc_account.project_id
  project_id     = length(var.project_id) > 0 ? var.project_id : data.google_project.selected[0].project_id

  bucket_name = length(var.existing_bucket_name) > 0 ? var.existing_bucket_name : (
    length(google_storage_bucket.lacework_bucket) > 0 ? google_storage_bucket.lacework_bucket[0].name : var.existing_bucket_name
  )

  sink_name = length(var.existing_sink_name) > 0 ? var.existing_sink_name : (
    var.org_integration ? "${var.prefix}-${var.organization_id}-lacework-sink-${random_id.uniq.hex}" : "${var.prefix}-lacework-sink-${random_id.uniq.hex}"
  )

  exclude_folders  = length(var.folders_to_exclude) != 0
  explicit_folders = length(var.folders_to_include) != 0

  logging_sink_writer_identity = length(var.existing_sink_name) > 0 ? null : (
    (var.org_integration && !(local.exclude_folders || local.explicit_folders)) ? (
      [google_logging_organization_sink.lacework_organization_sink[0].writer_identity]
      ) : (
      (var.org_integration && (local.exclude_folders || local.explicit_folders)) ? (
        concat(
          [for v in google_logging_folder_sink.lacework_folder_sink : v.writer_identity],
          [for v in google_logging_project_sink.lacework_root_project_sink : v.writer_identity]
        )
        ) : (
        [google_logging_project_sink.lacework_project_sink[0].writer_identity]
      )
    )
  )

  service_account_name = var.use_existing_service_account ? (
    var.service_account_name
    ) : (
    length(var.service_account_name) > 0 ? var.service_account_name : "${var.prefix}-${random_id.uniq.hex}"
  )

  service_account_json_key = jsondecode(var.use_existing_service_account ? (
    base64decode(var.service_account_private_key)
    ) : (
    base64decode(google_service_account_key.lacework[0].private_key)
  ))

  bucket_roles = length(var.existing_sink_name) > 0 ? (
    {
      "roles/storage.objectViewer" = [
        "serviceAccount:${local.service_account_json_key.client_email}"
      ]
    }) : (
    {
      "roles/storage.admin" = [
        "projectEditor:${local.project_id}",
        "projectOwner:${local.project_id}"
      ],
      "roles/storage.objectCreator" = local.logging_sink_writer_identity,
      "roles/storage.objectViewer" = [
        "serviceAccount:${local.service_account_json_key.client_email}",
        "projectViewer:${local.project_id}"
      ]
  })

  log_filter_map = {
    default                = "(protoPayload.@type=type.googleapis.com/google.cloud.audit.AuditLog) AND NOT (protoPayload.methodName:\"storage.objects\")"
    k8s_only               = "(protoPayload.@type=type.googleapis.com/google.cloud.audit.AuditLog) AND NOT (protoPayload.serviceName=\"k8s.io\") AND NOT (protoPayload.methodName:\"storage.objects\")"
    workspace_only         = "(protoPayload.@type=type.googleapis.com/google.cloud.audit.AuditLog) AND NOT (protoPayload.methodName:\"storage.objects\") AND NOT (protoPayload.serviceName:\"login.googleapis.com\")"
    k8s_workspace_combined = "(protoPayload.@type=type.googleapis.com/google.cloud.audit.AuditLog) AND NOT (protoPayload.serviceName=\"k8s.io\") AND NOT (protoPayload.serviceName:\"login.googleapis.com\") AND NOT (protoPayload.methodName:\"storage.objects\")"
  }

  log_filter = length(var.custom_filter) > 0 ? (var.custom_filter) : (
    !var.k8s_filter && !var.google_workspace_filter ? ("${lookup(local.log_filter_map, "default")}") : (
      var.k8s_filter && !var.google_workspace_filter ?
      "${lookup(local.log_filter_map, "k8s_only")}" : (
        !var.k8s_filter && var.google_workspace_filter ?
        "${lookup(local.log_filter_map, "workspace_only")}" : (
          "${lookup(local.log_filter_map, "k8s_workspace_combined")}"
        )
      )
    )
  )

  folders = [
    (var.org_integration && local.exclude_folders) ? (
      setsubtract(data.google_folders.my-org-folders[0].folders[*].name, var.folders_to_exclude)
      ) : (
      var.org_integration && local.explicit_folders) ? (
      var.folders_to_include
      ) : (
      toset([])
    )
  ]

  root_projects = [
    (var.org_integration && local.exclude_folders && var.include_root_projects) ? (
      toset(data.google_projects.my-org-projects[0].projects[*].project_id)
      ) : (
      toset([])
    )
  ]

  version_file   = "${abspath(path.module)}/VERSION"
  module_name    = "terraform-gcp-audit-log"
  module_version = fileexists(local.version_file) ? file(local.version_file) : ""
}

resource "random_id" "uniq" {
  byte_length = 4
}

data "google_project" "selected" {
  count = length(var.project_id) > 0 ? 0 : 1
}

data "google_folders" "my-org-folders" {
  count     = (var.org_integration && local.exclude_folders) ? 1 : 0
  parent_id = "organizations/${var.organization_id}"
}

data "google_projects" "my-org-projects" {
  count  = (local.exclude_folders && var.include_root_projects) ? 1 : 0
  filter = "parent.id=${var.organization_id}"
}

resource "google_project_service" "required_apis" {
  for_each = var.required_apis
  project  = local.project_id
  service  = each.value

  disable_on_destroy = false
}

/* module "lacework_at_svc_account" {
  source               = "lacework/service-account/gcp"
  version              = "~> 2.0"
  create               = var.use_existing_service_account ? false : true
  service_account_name = local.service_account_name
  project_id           = local.project_id
} */

resource "google_service_account" "lacework" {
  count        = var.create ? 1 : 0
  project      = local.project_id
  account_id   = local.service_account_name
  display_name = local.service_account_name
}

resource "google_service_account_key" "lacework" {
  count        = var.create ? 1 : 0
  service_account_id = google_service_account.lacework[count.index].name
}

resource "google_storage_bucket" "lacework_bucket" {
  count                       = length(var.existing_bucket_name) > 0 ? 0 : 1
  project                     = local.project_id
  name                        = coalesce(var.custom_bucket_name, "${var.prefix}-${random_id.uniq.hex}")
  force_destroy               = var.bucket_force_destroy
  location                    = var.bucket_region
  depends_on                  = [google_project_service.required_apis]
  uniform_bucket_level_access = var.enable_ubla
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rule_age > 0 ? [1] : []
    content {
      condition {
        age = var.lifecycle_rule_age
      }
      action {
        type = "Delete"
      }
    }
  }
  labels = merge(var.labels, var.bucket_labels)
}

resource "google_storage_bucket_iam_binding" "policies" {
  for_each = local.bucket_roles
  role     = each.key
  members  = each.value
  bucket   = local.bucket_name
}

resource "google_pubsub_topic" "lacework_topic" {
  name       = "${var.prefix}-lacework-topic-${random_id.uniq.hex}"
  project    = local.project_id
  depends_on = [google_project_service.required_apis]
  labels     = merge(var.labels, var.pubsub_topic_labels)
}

# By calling this data source we are accessing the storage service
# account and therefore, Google will created for us. If we don't
# ask for it, Google doesn't create it by default, more docs at:
# => https://cloud.google.com/storage/docs/projects#service-accounts
#
# If the service account is not there, we could add a local-exec
# provisioner to call an API that is documented at:
# => https://cloud.google.com/storage-transfer/docs/reference/rest/v1/googleServiceAccounts/get
data "google_storage_project_service_account" "lw" {
  project = local.project_id
}

resource "google_pubsub_topic_iam_binding" "topic_publisher" {
  members = ["serviceAccount:${data.google_storage_project_service_account.lw.email_address}"]
  role    = "roles/pubsub.publisher"
  project = local.project_id
  topic   = google_pubsub_topic.lacework_topic.name
}

resource "google_pubsub_subscription" "lacework_subscription" {
  project                    = local.project_id
  name                       = "${var.prefix}-${local.project_id}-lacework-subscription-${random_id.uniq.hex}"
  topic                      = google_pubsub_topic.lacework_topic.name
  ack_deadline_seconds       = 300
  message_retention_duration = "432000s"
  labels                     = merge(var.labels, var.pubsub_subscription_labels)
}

resource "google_logging_project_sink" "lacework_project_sink" {
  count                  = length(var.existing_sink_name) > 0 ? 0 : (var.org_integration ? 0 : 1)
  project                = local.project_id
  name                   = local.sink_name
  destination            = "storage.googleapis.com/${local.bucket_name}"
  unique_writer_identity = true

  filter = local.log_filter
}

resource "google_logging_organization_sink" "lacework_organization_sink" {
  count            = length(var.existing_sink_name) > 0 ? 0 : ((var.org_integration && !(local.exclude_folders || local.explicit_folders) ? 1 : 0))
  name             = local.sink_name
  org_id           = var.organization_id
  destination      = "storage.googleapis.com/${local.bucket_name}"
  include_children = true

  filter = local.log_filter
}

resource "google_logging_folder_sink" "lacework_folder_sink" {
  for_each         = local.folders[0]
  name             = local.sink_name
  folder           = each.value
  destination      = "storage.googleapis.com/${local.bucket_name}"
  include_children = true

  filter = local.log_filter
}

resource "google_logging_project_sink" "lacework_root_project_sink" {
  for_each               = local.root_projects[0]
  project                = each.value
  name                   = local.sink_name
  destination            = "storage.googleapis.com/${local.bucket_name}"
  unique_writer_identity = true

  filter = local.log_filter
}

resource "google_pubsub_subscription_iam_binding" "lacework" {
  project      = local.project_id
  role         = "roles/pubsub.subscriber"
  members      = ["serviceAccount:${local.service_account_json_key.client_email}"]
  subscription = google_pubsub_subscription.lacework_subscription.name
}

resource "google_storage_notification" "lacework_notification" {
  bucket         = local.bucket_name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.lacework_topic.id
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [
    google_pubsub_topic_iam_binding.topic_publisher,
    google_storage_bucket_iam_binding.policies
  ]
}

resource "google_project_iam_member" "for_lacework_service_account" {
  project = local.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${local.service_account_json_key.client_email}"
}

resource "google_organization_iam_member" "for_lacework_service_account" {
  count  = var.org_integration ? 1 : 0
  org_id = var.organization_id
  role   = "roles/resourcemanager.organizationViewer"
  member = "serviceAccount:${local.service_account_json_key.client_email}"
}

# wait for X seconds for things to settle down in the GCP side
# before trying to create the Lacework external integration
/* resource "time_sleep" "wait_time" {
  create_duration = var.wait_time
  depends_on = [
    google_storage_notification.lacework_notification,
    google_pubsub_subscription_iam_binding.lacework,
    module.lacework_at_svc_account,
    google_project_iam_member.for_lacework_service_account,
    google_organization_iam_member.for_lacework_service_account
  ]
}

resource "lacework_integration_gcp_at" "default" {
  name           = var.lacework_integration_name
  resource_id    = local.resource_id
  resource_level = local.resource_level
  subscription   = google_pubsub_subscription.lacework_subscription.id
  credentials {
    client_id      = local.service_account_json_key.client_id
    private_key_id = local.service_account_json_key.private_key_id
    client_email   = local.service_account_json_key.client_email
    private_key    = local.service_account_json_key.private_key
  }
  depends_on = [time_sleep.wait_time]
}

data "lacework_metric_module" "lwmetrics" {
  name    = local.module_name
  version = local.module_version
} */
