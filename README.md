# Personal Blog

Personal blog, backed up by Hugo.

## Infrastructure

Initialize your AWS account. Terraform AWS provider will look for default credentials in _~/.aws/credentials_.

```sh
terraform init
terraform plan -out plan.tfplan
terraform apply "plan.tfplan"
```
