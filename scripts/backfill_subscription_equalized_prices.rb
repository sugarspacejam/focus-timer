require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

KEY_ID = 'KS8L66PG43'
ISSUER_ID = '9e48801a-8319-48b9-994a-84b06bd86f86'
PRIVATE_KEY_PATH = '/Volumes/waffleman/chentoledano/Projects-new/focus-timer/.creds/AuthKey_KS8L66PG43.p8'
BASE_URL = 'https://api.appstoreconnect.apple.com'

if ARGV.length != 2
  raise 'Usage: ruby scripts/backfill_subscription_equalized_prices.rb <SUBSCRIPTION_ID> <SOURCE_PRICE_POINT_ID>'
end

subscription_id = ARGV[0]
source_price_point_id = ARGV[1]

if File.exist?(PRIVATE_KEY_PATH) == false
  raise "Missing private key file at #{PRIVATE_KEY_PATH}"
end

private_key = OpenSSL::PKey.read(File.read(PRIVATE_KEY_PATH))

if private_key.is_a?(OpenSSL::PKey::EC) == false
  raise 'Private key must be an EC key for ES256'
end

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def jwt_token(private_key)
  header = {
    alg: 'ES256',
    kid: KEY_ID,
    typ: 'JWT'
  }

  payload = {
    iss: ISSUER_ID,
    aud: 'appstoreconnect-v1',
    exp: Time.now.to_i + (20 * 60)
  }

  signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
  der_signature = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  asn1_signature = OpenSSL::ASN1.decode(der_signature)

  if asn1_signature.value.length != 2
    raise 'Unexpected ECDSA signature structure'
  end

  r = asn1_signature.value[0].value
  s = asn1_signature.value[1].value
  r_hex = r.to_s(16).rjust(64, '0')
  s_hex = s.to_s(16).rjust(64, '0')
  raw_signature = [r_hex, s_hex].pack('H*H*')
  "#{signing_input}.#{base64url(raw_signature)}"
end

def request_json(method, path, token, body = nil)
  uri = URI.join(BASE_URL, path)
  request_class = case method
  when 'GET'
    Net::HTTP::Get
  when 'POST'
    Net::HTTP::Post
  else
    raise "Unsupported method: #{method}"
  end

  request = request_class.new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Accept'] = 'application/json'

  if body
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
  end

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.request(request)
  end

  parsed_body = if response.body && response.body.empty? == false
    JSON.parse(response.body)
  else
    nil
  end

  {
    status: response.code.to_i,
    body: parsed_body
  }
end

token = jwt_token(private_key)
equalizations_response = request_json(
  'GET',
  "/v1/subscriptionPricePoints/#{source_price_point_id}/equalizations?limit=200",
  token
)

if equalizations_response[:status] != 200
  puts JSON.pretty_generate(equalizations_response)
  raise 'Failed to fetch equalized subscription price points'
end

price_point_ids = equalizations_response.fetch(:body).fetch('data').map { |item| item.fetch('id') }.uniq

puts JSON.pretty_generate(event: 'equalizations_loaded', subscriptionId: subscription_id, total: price_point_ids.length)

price_point_ids.each_with_index do |price_point_id, index|
  payload = {
    data: {
      type: 'subscriptionPrices',
      attributes: {},
      relationships: {
        subscription: {
          data: {
            type: 'subscriptions',
            id: subscription_id
          }
        },
        subscriptionPricePoint: {
          data: {
            type: 'subscriptionPricePoints',
            id: price_point_id
          }
        }
      }
    }
  }

  response = request_json('POST', '/v1/subscriptionPrices', token, payload)

  if response[:status] < 200 || response[:status] >= 300
    puts JSON.pretty_generate(event: 'price_apply_failed', index: index + 1, total: price_point_ids.length, pricePointId: price_point_id, response: response)
    raise 'Failed to apply one or more subscription price points'
  end

  if ((index + 1) % 25).zero?
    puts JSON.pretty_generate(event: 'price_apply_progress', completed: index + 1, total: price_point_ids.length)
  end
end

puts JSON.pretty_generate(event: 'price_apply_done', subscriptionId: subscription_id, total: price_point_ids.length)
