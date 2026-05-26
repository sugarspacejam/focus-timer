require 'json'
require 'net/http'
require 'openssl'
require 'base64'
require 'time'
require 'uri'

KEY_ID = 'KS8L66PG43'
ISSUER_ID = '9e48801a-8319-48b9-994a-84b06bd86f86'
PRIVATE_KEY_PATH = '/Volumes/waffleman/chentoledano/Projects-new/focus-timer/.creds/AuthKey_KS8L66PG43.p8'
BASE_URL = 'https://api.appstoreconnect.apple.com'

def jwt
  private_key = OpenSSL::PKey::EC.new(File.read(PRIVATE_KEY_PATH))
  now = Time.now.to_i
  payload = {
    iss: ISSUER_ID,
    iat: now - 300,
    exp: now + 1200,
    aud: 'appstoreconnect-v1'
  }
  headers = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
  header_encoded = Base64.urlsafe_encode64(headers.to_json, padding: false)
  payload_encoded = Base64.urlsafe_encode64(payload.to_json, padding: false)
  signing_input = "#{header_encoded}.#{payload_encoded}"
  signature = private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
  signature_encoded = Base64.urlsafe_encode64(signature, padding: false)
  "#{header_encoded}.#{payload_encoded}.#{signature_encoded}"
end

def get(path)
  uri = URI.join(BASE_URL, path)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{jwt}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  puts "Status: #{res.code}"
  puts "Body: #{res.body}"
  JSON.parse(res.body)
end

data = get('/v1/apps/6761027000/appStoreVersions')
puts JSON.pretty_generate(data)
versions = data['data']
if versions
  versions.each do |v|
    attrs = v['attributes']
    puts "Version: #{attrs['versionString']}, State: #{attrs['appStoreState']}, Platform: #{attrs['platform']}"
  end
else
  puts "No versions found"
end
