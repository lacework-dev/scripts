output "service_account_name" {
  value       = local.service_account_name
  description = "The Service Account name"
}

output "service_account_private_key" {
  value       = local.service_account_json_key
  description = "The private key in JSON format, base64 encoded"
  sensitive = true
}

output "bucket_name" {
  value       = local.bucket_name
  description = "The storage bucket name"
}

output "pubsub_topic_name" {
  value       = google_pubsub_topic.lacework_topic.name
  description = "The PubSub topic name"
}

output "sink_name" {
  value       = local.sink_name
  description = "The sink name"
}
