# Personal Blog

Personal blog, backed up by Hugo.

## Infrastructure

Initialize your AWS account. Terraform AWS provider will look for default credentials in _~/.aws/credentials_.

To provision the required resources, you have to do it in two steps.
First create the certificate, then everything else.

```sh
cd ./infrastructure
terraform init
terraform plan -out cert.tfplan -target aws_acm_certificate.cert
terraform apply cert.tfplan
terraform plan -out everything.tfplan
terraform plan everything.tfplan
```
