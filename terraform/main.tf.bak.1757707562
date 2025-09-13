terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.28.1"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}

resource "kubernetes_namespace" "ns" {
  metadata { name = var.namespace }
}

resource "helm_release" "dvp_worker" {
  name       = "dvp"
  namespace  = kubernetes_namespace.ns.metadata[0].name
  chart      = "../charts/dvp-worker"

  set {
    name  = "image.repository"
    value = var.image_repository
  }
  set {
    name  = "image.tag"
    value = var.image_tag
  }
  set { name = "env.RPC_URL"            value = var.rpc_url }
  set { name = "env.CONTRACT_ADDRESS"    value = var.contract_address }
  set { name = "env.REGISTRAR_API_URL"   value = var.registrar_api_url }
  set { name = "env.START_BLOCK"         value = var.start_block }

  set_sensitive { name = "secretEnv.ORACLE_PRIVATE_KEY"  value = var.oracle_private_key }
  set_sensitive { name = "secretEnv.REGISTRAR_API_TOKEN" value = var.registrar_api_token }
}
