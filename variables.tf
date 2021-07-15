# General varaibles used by multiple resources
variable "tags" {
  description = "Default tags to be used with AWS resources"
  type        = map(string)
  default = {
    Application = "Quest"
    Billing     = "Rearc"
    Contact     = "daniel.babel@gmail.com"
    Provisioner = "Terraform"
  }
}
