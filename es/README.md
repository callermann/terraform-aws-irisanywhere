# Deploying GrayMeta Iris Anywhere AWS OpenSearch with Terraform

The following contains instructions for deploying OpenSearch (within a VPC) with Iris Anywhere into an AWS environment. This module creates a domain with two instances for HA. We enable end-to-end encryption along with data encryption at rest.

Prerequisites:
* Stored credentials in [Secrets Manager](#creating-secrets-for-iris-anywhere) prior to deploying with the specific attributes specified for OpenSearch.
* Secret and Access keys for the IAM user account created by this module. These must be populated in AWS Secrets Manager see below. These are used to authenticate with OpenSearch when managing indexes.
* Iris Anywhere ASG set search_enabled to "true".
* Certificates created or imported in AWS Certificate Manager.
* OpenSearch requires two subnets for high availability.
* Terraform 12, 13 & 14 compatible.
* `version` - Current version is `v0.0.11`.

## Example Usage

```hcl
provider "aws" {
  region  = "us-west-2"
  profile = "my-aws-profile"
}

module "ia-opensearch" {
  source = "github.com/graymeta/terraform-aws-irisanywhere//es?ref=v0.0.11"

domain                                    = "es-domain-name" 
instance_type                             = "m4.xlarge.elasticsearch"
subnet_id                                 = ["subnet-foo1", "subnet-foo2"]
custom_endpoint                           = "youres.domain.com"
custom_endpoint_certificate_arn           = "arn:aws:acm:region:########:certificate/1234"
encrypt_at_rest_kms_key_id                = "arn:aws:kms:region:########:key/1234"
ia_secret_arn                             = "arn:aws:secretsmanager:region:##########/credname"
bucketlist                                = "s3bucket1"

}

```
### Arguement Reference:
* `domain` - (Required) List of network cidr that have access.  Default to `["0.0.0.0/0"]`
* `instance_type` - (Required) Elasticsearch instance type for data nodes in the cluster.
* `subnet_id` - (Required) A list of subnet IDs to launch resources in.
* `custom_endpoint` - (Required) Specifies custom FQDN for the domain.
* `custom_endpoint_certificate_arn` - (Required) ARN of certificate for configurating Iris Anywhere.
* `encrypt_at_rest_kms_key_id` - (Required) ARN of ES key in Key Management Service to support encryption at rest.
* `tags` -  (Optional) A map of the additional tags.
* `volume_type` - (Optional) EBS volume type. Default to `gp2`.
* `volume_size` - (Optional) EBS volume size. Default to `10`.

The following secret keys must be set for OpenSearch to work properly.

    os_region          = ""
    os_endpoint        = ""
    os_accessid        = ""
    os_secretkey       = ""



### Attributes Reference: