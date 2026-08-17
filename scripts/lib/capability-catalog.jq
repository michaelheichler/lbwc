{
  schema_version: 1,
  source: {
    binary_path: $binary_path,
    version: $version,
    sha256: $sha256,
    detected_at: $detected_at
  },
  models: $composed[0].models,
  host_agent_enum: $composed[0].host_agent_enum,
  agent_model_ids: $composed[0].agent_model_ids,
  reasoning: {
    scope: "global",
    accepted_values: $reasoning[0],
    model_associations: $associations[0]
  }
}
