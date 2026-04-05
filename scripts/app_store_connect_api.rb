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

if ARGV.length < 2
  raise 'Usage: ruby scripts/app_store_connect_api.rb <METHOD> <PATH> [BODY_FILE]'
end

method = ARGV[0].upcase
path = ARGV[1]
body_file = ARGV[2]

if ['GET', 'POST', 'PATCH', 'DELETE'].include?(method) == false
  raise "Unsupported method: #{method}"
end

if path.start_with?('/') == false
  raise 'PATH must start with /'
end

if File.exist?(PRIVATE_KEY_PATH) == false
  raise "Missing private key file at #{PRIVATE_KEY_PATH}"
end

private_key_pem = File.read(PRIVATE_KEY_PATH)
private_key = OpenSSL::PKey.read(private_key_pem)

if private_key.is_a?(OpenSSL::PKey::EC) == false
  raise 'Private key must be an EC key for ES256'
end

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

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

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
jwt = "#{signing_input}.#{base64url(raw_signature)}"

uri = URI.join(BASE_URL, path)
request_class = case method
when 'GET'
  Net::HTTP::Get
when 'POST'
  Net::HTTP::Post
when 'PATCH'
  Net::HTTP::Patch
when 'DELETE'
  Net::HTTP::Delete
else
  raise "Unhandled method: #{method}"
end

request = request_class.new(uri)
request['Authorization'] = "Bearer #{jwt}"
request['Accept'] = 'application/json'

if body_file
  if File.exist?(body_file) == false
    raise "Missing body file at #{body_file}"
  end
  request['Content-Type'] = 'application/json'
  request.body = File.read(body_file)
end

response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
  http.request(request)
end

parsed_body = if response.body && response.body.empty? == false
  JSON.parse(response.body)
else
  nil
end

puts JSON.pretty_generate(
  status: response.code.to_i,
  headers: response.each_header.to_h,
  body: parsed_body
)
