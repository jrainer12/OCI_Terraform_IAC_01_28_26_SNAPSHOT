terraform {
  backend "s3" {
    # OCI Object Storage uses the S3-compatible API
    # This allows Terraform to use OCI Object Storage as a remote backend
    # 
    # Required values (set via -backend-config):
    # - bucket: Name of the Object Storage bucket (default: "terraform-state")
    # - key: Path to state file in bucket (default: "oci-oke/terraform.tfstate")
    # - region: OCI region (e.g., "us-ashburn-1")
    # - endpoints.s3: S3-compatible endpoint (format: https://<namespace>.compat.objectstorage.<region>.oraclecloud.com)
    #
    # Credentials (set via environment variables):
    # - AWS_ACCESS_KEY_ID: OCI S3-compatible access key ID (NOT your tenancy OCID!)
    # - AWS_SECRET_ACCESS_KEY: OCI S3-compatible secret access key (NOT your API private key!)
    #
    # To create S3-compatible keys:
    # OCI Console → Identity → Users → Your User → Customer Secret Keys → Generate Secret Key
    #
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style             = true
  }
}