provider "oci" {
  auth                = "APIKey"
  config_file_profile = "DEFAULT" # uses ~/.oci/config
  region              = var.region
}