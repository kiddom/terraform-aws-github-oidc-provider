provider "aws" {
  region                      = "us-east-2"
  access_key                  = "mock-access-key"
  secret_key                  = "mock-secret-key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

run "immutable_repository_subject" {
  command = plan

  variables {
    repositories = ["kiddom@2820554/grafana@1342199943"]
  }

  assert {
    condition     = contains(local.repository_subjects, "repo:kiddom@2820554/grafana@1342199943:*")
    error_message = "The immutable repository prefix must be emitted verbatim with a subject wildcard."
  }
}

run "standard_repository_subject" {
  command = plan

  variables {
    repositories = ["kiddom/grafana"]
  }

  assert {
    condition     = contains(local.repository_subjects, "repo:kiddom/grafana:*")
    error_message = "Existing organization/repository subjects must remain unchanged."
  }
}
