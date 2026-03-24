# Infra Provisioning IAC

## Description
Uses Terraform to create an S3 bucket and a CloudFront distribution mapped to the S3 bucket.

## Instructions

1. Create an OIDC role in the target AWS account that GitHub Actions can assume.
2. Run the GitHub Actions workflow. The workflow requires:
   - AWS Account ID
   - S3 bucket name
   - Enable SPA redirect (true/false)
   - Issue custom domain certificate (true/false)
   - Custom domain name
3. Review the Terraform plan produced by the workflow and approve the apply (the apply job is gated by an environment approval).
