class ArtifactSerializer
  ATTRIBUTES = %i[id artifact_type sequence payload created_at].freeze

  def initialize(artifact)
    @artifact = artifact
  end

  def as_json
    ATTRIBUTES.each_with_object({}) { |attr, memo| memo[attr] = @artifact.public_send(attr) }
  end

  def self.collection(artifacts)
    artifacts.map { |a| new(a).as_json }
  end
end
