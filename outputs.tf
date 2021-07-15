########################################
## Outputs
########################################
output "web_urls" {
  description = "Supported URL's to the app (excluding https as it's not implemented)"
  value = {
    index  = "http://${aws_lb.app.dns_name}"
    docker = "http://${aws_lb.app.dns_name}/docker"
    lb     = "http://${aws_lb.app.dns_name}/loadbalanced"
  }
}

output "codebuild" {
  description = "Codebuild project name and the region it's found in"
  value = {
    name   = aws_codebuild_project.build.name
    region = var.region
  }
}
