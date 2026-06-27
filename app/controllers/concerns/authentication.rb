module Authentication
  extend ActiveSupport::Concern

  class VerificationError < StandardError; end

  JWKS_CACHE_TTL = 10.minutes
  CLOCK_LEEWAY = 30
  JWKS_CACHE_MUTEX = Mutex.new

  mattr_accessor :jwks_cache, instance_accessor: false

  def current_user_id
    @current_user_id
  end

  def authenticate!
    token = bearer_token
    return render_unauthorized if token.blank?

    claims = verify_token!(token)
    @current_user_id = claims["sub"]
    return render_unauthorized if @current_user_id.blank?
  rescue VerificationError, JWT::DecodeError, JWT::JWKError,
         OpenSSL::PKey::PKeyError, JSON::ParserError, ArgumentError,
         KeyError, SocketError, SystemCallError, Timeout::Error => e
    Rails.logger.info("JWT verification failed: #{e.class}: #{e.message}")
    render_unauthorized
  end

  private

  def verify_token!(token)
    parts = token.split(".")
    raise VerificationError, "malformed token" unless parts.length == 3

    header = JSON.parse(b64url_decode(parts[0]))

    return verify_bridge_jwt!(token) if header["alg"] == "HS256"

    verify_jwks_token!(header, parts)
  end

  def verify_bridge_jwt!(token)
    secret = ENV.fetch("NEON_AUTH_BRIDGE_SECRET")
    payload, _header = JWT.decode(token, secret, true,
      algorithms: ["HS256"],
      leeway: CLOCK_LEEWAY,
      required_claims: ["sub", "exp"])
    payload
  rescue JWT::DecodeError => e
    raise VerificationError, "bridge JWT invalid: #{e.message}"
  end

  def verify_jwks_token!(header, parts)
    alg = header["alg"]
    raise VerificationError, "unsupported alg #{alg.inspect}" unless %w[EdDSA RS256].include?(alg)

    jwk = find_jwk(header["kid"])
    raise VerificationError, "no JWKS key for kid #{header['kid'].inspect}" if jwk.nil?

    signing_input = "#{parts[0]}.#{parts[1]}"
    verify_jwks_signature!(jwk, alg, signing_input, b64url_decode(parts[2]))

    claims = JSON.parse(b64url_decode(parts[1]))
    validate_claims!(claims)
    claims
  end

  def verify_jwks_signature!(jwk, alg, signing_input, signature)
    verified =
      case alg
      when "EdDSA"
        raise VerificationError, "expected OKP key for EdDSA" unless jwk["kty"] == "OKP"
        OpenSSL::PKey.new_raw_public_key("ED25519", b64url_decode(jwk["x"])).verify(nil, signature, signing_input)
      when "RS256"
        JWT::JWK.import(jwk.transform_keys(&:to_sym)).verify_key.verify(
          OpenSSL::Digest.new("SHA256"), signature, signing_input
        )
      end
    raise VerificationError, "signature verification failed (#{alg})" unless verified
  end

  def validate_claims!(claims)
    now = Time.now.to_i
    raise VerificationError, "missing exp claim" unless claims["exp"]
    raise VerificationError, "token expired" if now > claims["exp"].to_i + CLOCK_LEEWAY

    if (nbf = claims["nbf"])
      raise VerificationError, "token not yet valid" if now < nbf.to_i - CLOCK_LEEWAY
    end

    if (expected_iss = ENV["NEON_AUTH_ISSUER"]).present? && claims["iss"] != expected_iss
      raise VerificationError, "issuer mismatch: #{claims['iss'].inspect} != #{expected_iss.inspect}"
    end

    if (expected_aud = ENV["NEON_AUTH_AUDIENCE"]).present? &&
       !Array(claims["aud"]).include?(expected_aud)
      raise VerificationError, "audience mismatch: #{claims['aud'].inspect}"
    end
  end

  def bearer_token
    request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
  end

  def render_unauthorized
    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def find_jwk(kid)
    return nil if kid.blank?
    match = ->(keys) { keys.find { |k| k["kid"] == kid } }
    match.call(jwks_keys) || match.call(jwks_keys(force: true))
  end

  def jwks_keys(force: false)
    cache = Authentication.jwks_cache
    return cache[:keys] if !force && cache && cache[:fetched_at] >= JWKS_CACHE_TTL.ago

    JWKS_CACHE_MUTEX.synchronize do
      cache = Authentication.jwks_cache
      if force || cache.nil? || cache[:fetched_at] < JWKS_CACHE_TTL.ago
        cache = Authentication.jwks_cache = {
          keys: fetch_jwks.fetch("keys"),
          fetched_at: Time.current
        }
      end
      cache[:keys]
    end
  end

  def fetch_jwks
    JSON.parse(Net::HTTP.get(URI(ENV.fetch("NEON_AUTH_JWKS_URL"))))
  end

  def b64url_decode(str)
    Base64.urlsafe_decode64(str + "=" * ((4 - str.length % 4) % 4))
  end
end
