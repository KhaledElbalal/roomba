module AuthHelpers
  def rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.generate(2048)
  end

  def stub_jwks(kid: "test-key-1")
    jwk       = JWT::JWK.new(rsa_key, kid: kid)
    jwks_hash = { keys: [ jwk.export.merge(alg: "RS256", use: "sig") ] }
    Authentication.jwks_cache = nil
    allow_any_instance_of(Authentication)
      .to receive(:fetch_jwks)
      .and_return(jwks_hash.deep_stringify_keys)
  end

  def jwt_token(user_id, kid: "test-key-1")
    JWT.encode(
      {
        "sub" => user_id,
        "iss" => ENV["NEON_AUTH_ISSUER"],
        "aud" => ENV["NEON_AUTH_AUDIENCE"],
        "exp" => (Time.now + 300).to_i,
        "iat" => Time.now.to_i
      },
      rsa_key,
      "RS256",
      { kid: kid }
    )
  end

  def auth_headers(user_id)
    { "Authorization" => "Bearer #{jwt_token(user_id)}" }
  end
end
