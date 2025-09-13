output "namespace" {
  value = kubernetes_namespace.dvp.metadata[0].name
}

output "release_name" {
  value = helm_release.dvp_worker.name
}

output "image" {
  value = "${var.image_repository}:${var.image_tag}"
}

output "contract_address" {
  value = var.contract_address
}
