output "service_account_name" {
  value       = local.service_account_name
  description = "The Service Account name"
}

output "service_account_private_key" {
  value       = length(var.service_account_private_key) > 0 ? var.service_account_private_key : base64decode(google_service_account_key.lacework[0].private_key)
  description = "The private key in JSON format, base64 encoded"
  sensitive = true
}

output "service_account_email" {
  value       = google_service_account.lacework[0].email
  description = "The Service Account email"
}

output "service_account_key_id" {
  value       = google_service_account_key.lacework[0].id
  description = "The Service Account private key ID"
}