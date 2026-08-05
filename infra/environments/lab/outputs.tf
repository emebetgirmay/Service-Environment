output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "cluster_name" {
  value = module.ecs_platform.cluster_name
}

output "service_connect_namespace" {
  value = module.ecs_platform.service_connect_namespace_name
}

# Push images here before an apply that references a new tag. See
# docs/iac/deployment-sequence.md for the first-time bootstrap order.
output "ecr_repository_urls" {
  value = {
    service_a = module.service_a.repository_url
    service_b = module.service_b.repository_url
    service_c = module.service_c.repository_url
  }
}
