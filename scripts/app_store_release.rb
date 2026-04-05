require 'base64'
require 'json'
require 'fileutils'
require 'net/http'
require 'openssl'
require 'time'
require 'uri'

KEY_ID = 'KS8L66PG43'
ISSUER_ID = '9e48801a-8319-48b9-994a-84b06bd86f86'
PRIVATE_KEY_PATH = '/Volumes/waffleman/chentoledano/Projects-new/focus-timer/.creds/AuthKey_KS8L66PG43.p8'
BASE_URL = 'https://api.appstoreconnect.apple.com'

APP_BUNDLE_ID = 'com.5minutesblockstimer'

ROOT_DIR = File.expand_path(File.join(__dir__, 'appstore'))
METADATA_PATH = File.join(ROOT_DIR, 'metadata', 'en-US.json')
SCREENSHOTS_SOURCE_DIR = File.join(ROOT_DIR, 'screenshots', 'source')
SCREENSHOTS_GENERATED_DIR = File.join(ROOT_DIR, 'screenshots', '_generated')

ALLOWED_SIZES_BY_DISPLAY_TYPE = {
  'APP_IPHONE_65' => [
    [1242, 2688],
    [2688, 1242],
    [1284, 2778],
    [2778, 1284]
  ],
  'APP_IPHONE_67' => [
    [1290, 2796],
    [2796, 1290],
    [1320, 2868],
    [2868, 1320],
    [1260, 2736],
    [2736, 1260]
  ]
}.freeze

def fail!(message)
  raise message
end

def base64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

def jwt
  if File.exist?(PRIVATE_KEY_PATH) == false
    fail!("Missing private key file at #{PRIVATE_KEY_PATH}")
  end

  private_key_pem = File.read(PRIVATE_KEY_PATH)
  private_key = OpenSSL::PKey.read(private_key_pem)

  if private_key.is_a?(OpenSSL::PKey::EC) == false
    fail!('Private key must be an EC key for ES256')
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

  signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
  der_signature = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  asn1_signature = OpenSSL::ASN1.decode(der_signature)

  if asn1_signature.value.length != 2
    fail!('Unexpected ECDSA signature structure')
  end

  r = asn1_signature.value[0].value
  s = asn1_signature.value[1].value
  r_hex = r.to_s(16).rjust(64, '0')
  s_hex = s.to_s(16).rjust(64, '0')
  raw_signature = [r_hex, s_hex].pack('H*H*')

  "#{signing_input}.#{base64url(raw_signature)}"
end

def request(method, path, body: nil, headers: {})
  if path.start_with?('/') == false
    fail!('PATH must start with /')
  end

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
    fail!("Unsupported method: #{method}")
  end

  req = request_class.new(uri)
  req['Authorization'] = "Bearer #{jwt}"
  req['Content-Type'] = 'application/json'
  headers.each { |k, v| req[k] = v }
  req.body = body if body

  Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    res = http.request(req)
    parsed = if res.body && res.body.strip != ''
      JSON.parse(res.body)
    else
      nil
    end

    {
      status: res.code.to_i,
      headers: res.each_header.to_h,
      body: parsed,
      raw_body: res.body
    }
  end
end

def get_json!(path)
  res = request('GET', path)
  if res[:status] >= 300
    fail!("GET #{path} failed: #{res[:status]} #{res[:raw_body]}")
  end
  res[:body]
end

def post_json!(path, payload)
  res = request('POST', path, body: JSON.generate(payload))
  if res[:status] >= 300
    fail!("POST #{path} failed: #{res[:status]} #{res[:raw_body]}")
  end
  res[:body]
end

def patch_json!(path, payload)
  res = request('PATCH', path, body: JSON.generate(payload))
  if res[:status] >= 300
    fail!("PATCH #{path} failed: #{res[:status]} #{res[:raw_body]}")
  end
  res[:body]
end

def resolve_app_id!
  data = get_json!("/v1/apps?filter[bundleId]=#{APP_BUNDLE_ID}")
  apps = data.fetch('data')
  if apps.length != 1
    fail!("Expected exactly 1 app for bundle id #{APP_BUNDLE_ID}, got #{apps.length}")
  end
  apps.first.fetch('id')
end

def resolve_version_id!(app_id, version_string)
  data = get_json!("/v1/apps/#{app_id}/appStoreVersions")
  versions = data.fetch('data')
  match = versions.find { |v| v.fetch('attributes').fetch('versionString') == version_string && v.fetch('attributes').fetch('platform') == 'IOS' }
  if match.nil?
    fail!("Could not find IOS appStoreVersion #{version_string} for app #{app_id}")
  end
  match.fetch('id')
end

def resolve_localization_id!(version_id, locale)
  data = get_json!("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations")
  locs = data.fetch('data')
  match = locs.find { |l| l.fetch('attributes').fetch('locale') == locale }
  if match.nil?
    fail!("Could not find localization #{locale} for version #{version_id}")
  end
  match.fetch('id')
end

def load_metadata!
  if File.exist?(METADATA_PATH) == false
    fail!("Missing metadata file: #{METADATA_PATH}")
  end

  JSON.parse(File.read(METADATA_PATH))
end

def patch_localization!(localization_id, metadata)
  payload = {
    data: {
      type: "appStoreVersionLocalizations",
      id: localization_id,
      attributes: {
        promotionalText: metadata["promotionalText"],
        description: metadata["description"],
        keywords: metadata["keywords"],
        supportUrl: metadata["supportUrl"],
        marketingUrl: metadata["marketingUrl"]
      }
    }
  }
  puts patch_json!("/v1/appStoreVersionLocalizations/#{localization_id}", payload)
end

def list_screenshot_sets(localization_id)
  get_json!("/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets")
    .fetch('data')
end

def assert_screenshot_files!(files)
  if files.empty?
    fail!("No screenshots found in #{SCREENSHOTS_SOURCE_DIR}")
  end

  files.each do |path|
    ext = File.extname(path).downcase
    if ['.png', '.jpg', '.jpeg'].include?(ext) == false
      fail!("Unsupported screenshot format: #{path}")
    end

    image_size(path)
  end
end

def image_size(path)
  cmd = ['/usr/bin/sips', '-g', 'pixelWidth', '-g', 'pixelHeight', path]
  output = IO.popen(cmd, &:read)
  w = output[/pixelWidth:\s*(\d+)/, 1]
  h = output[/pixelHeight:\s*(\d+)/, 1]
  if w.nil? || h.nil?
    fail!("Failed to read image size for #{path}")
  end
  [w.to_i, h.to_i]
end

def ensure_screenshot_set!(localization_id, screenshot_display_type)
  existing = list_screenshot_sets(localization_id)
  match = existing.find { |s| s.fetch('attributes').fetch('screenshotDisplayType') == screenshot_display_type }
  return match.fetch('id') if match

  payload = {
    'data' => {
      'type' => 'appScreenshotSets',
      'attributes' => {
        'screenshotDisplayType' => screenshot_display_type
      },
      'relationships' => {
        'appStoreVersionLocalization' => {
          'data' => {
            'type' => 'appStoreVersionLocalizations',
            'id' => localization_id
          }
        }
      }
    }
  }

  created = post_json!('/v1/appScreenshotSets', payload)
  created.fetch('data').fetch('id')
end

def delete_json!(path)
  res = request('DELETE', path)
  if res[:status] >= 300
    fail!("DELETE #{path} failed: #{res[:status]} #{res[:raw_body]}")
  end
  res[:body]
end

def list_screenshot_ids_in_set!(screenshot_set_id)
  data = get_json!("/v1/appScreenshotSets/#{screenshot_set_id}/appScreenshots")
  data.fetch('data').map { |item| item.fetch('id') }
end

def clear_screenshot_set!(screenshot_set_id)
  ids = list_screenshot_ids_in_set!(screenshot_set_id)
  ids.each do |id|
    delete_json!("/v1/appScreenshots/#{id}")
    puts JSON.pretty_generate(event: 'screenshot_deleted', appScreenshotId: id, screenshotSetId: screenshot_set_id)
  end
end

def ensure_directory!(path)
  return if Dir.exist?(path)
  FileUtils.mkdir_p(path)
end

def sips_resample!(input_path, output_path, width, height)
  ensure_directory!(File.dirname(output_path))
  cmd = ['/usr/bin/sips', '--resampleHeightWidth', height.to_s, width.to_s, input_path, '--out', output_path]
  output = IO.popen(cmd, &:read)
  unless $?.success?
    fail!("sips resample failed for #{input_path}: #{output}")
  end
end

def generate_screenshots!(source_paths, target_display_type)
  allowed_sizes = ALLOWED_SIZES_BY_DISPLAY_TYPE[target_display_type]
  if allowed_sizes.nil?
    fail!("Unsupported screenshotDisplayType for generation: #{target_display_type}")
  end

  width, height = allowed_sizes.first
  out_dir = File.join(SCREENSHOTS_GENERATED_DIR, target_display_type)
  ensure_directory!(out_dir)

  source_paths.map do |source_path|
    base = File.basename(source_path, File.extname(source_path))
    out_path = File.join(out_dir, "#{base}_#{width}x#{height}.jpg")
    sips_resample!(source_path, out_path, width, height)

    out_w, out_h = image_size(out_path)
    if allowed_sizes.include?([out_w, out_h]) == false
      fail!("Generated screenshot has incorrect dimensions #{out_w}x#{out_h}: #{out_path}")
    end

    out_path
  end
end

def create_screenshot_reservation!(screenshot_set_id, file_path)
  file_size = File.size(file_path)
  file_name = File.basename(file_path)

  payload = {
    'data' => {
      'type' => 'appScreenshots',
      'attributes' => {
        'fileName' => file_name,
        'fileSize' => file_size
      },
      'relationships' => {
        'appScreenshotSet' => {
          'data' => {
            'type' => 'appScreenshotSets',
            'id' => screenshot_set_id
          }
        }
      }
    }
  }

  post_json!('/v1/appScreenshots', payload)
end

def upload_operations!(reservation)
  ops = reservation.fetch('data').fetch('attributes').fetch('uploadOperations')
  if ops.nil? || ops.empty?
    fail!('Missing uploadOperations in screenshot reservation response')
  end
  ops
end

def perform_upload!(operation, file_path)
  url = operation.fetch('url')
  method = operation.fetch('method')
  headers = operation['requestHeaders']

  if headers.nil?
    headers = []
  end

  unless headers.is_a?(Array)
    fail!("Unexpected upload operation requestHeaders shape: #{headers.class}")
  end

  uri = URI.parse(url)

  req_class = case method
  when 'PUT'
    Net::HTTP::Put
  when 'POST'
    Net::HTTP::Post
  else
    fail!("Unsupported upload method: #{method}")
  end

  req = req_class.new(uri)
  headers.each { |h| req[h.fetch('name')] = h.fetch('value') }
  req.body = File.binread(file_path)

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
    res = http.request(req)
    if res.code.to_i >= 300
      fail!("Upload failed: #{res.code} #{res.body}")
    end
  end
end

def commit_screenshot!(screenshot_id, reservation)
  checksum = reservation.fetch('data').fetch('attributes').fetch('sourceFileChecksum')

  attributes = {
    'uploaded' => true
  }

  if checksum
    attributes['sourceFileChecksum'] = checksum
  end

  payload = {
    'data' => {
      'type' => 'appScreenshots',
      'id' => screenshot_id,
      'attributes' => attributes
    }
  }

  patch_json!("/v1/appScreenshots/#{screenshot_id}", payload)
end

def ensure_screenshots!(screenshot_set_id, screenshot_paths)
  clear_screenshot_set!(screenshot_set_id)

  screenshot_paths.first(10).each do |path|
    reservation = create_screenshot_reservation!(screenshot_set_id, path)
    screenshot_id = reservation.fetch('data').fetch('id')

    upload_operations!(reservation).each do |op|
      perform_upload!(op, path)
    end

    commit_screenshot!(screenshot_id, reservation)
    puts JSON.pretty_generate(event: 'screenshot_uploaded', file: File.basename(path), appScreenshotId: screenshot_id)
  end
end

def attach_build!(version_id, build_id, metadata)
  payload = {
    data: {
      type: "builds",
      id: build_id
    }
  }
  puts patch_json!("/v1/appStoreVersions/#{version_id}/relationships/build", payload)
  patch_app_version!(version_id, metadata)
end

def patch_app_version!(version_id, metadata)
  payload = {
    data: {
      type: "appStoreVersions",
      id: version_id,
      attributes: {
        copyright: metadata["copyright"]
      }
    }
  }
  puts patch_json!("/v1/appStoreVersions/#{version_id}", payload)
end

metadata_file = load_metadata!
metadata = metadata_file
version_string = metadata_file.fetch('versionString')
locale = metadata_file.fetch('locale')
screenshot_display_types = metadata_file.fetch('screenshotDisplayTypes')

if screenshot_display_types.is_a?(Array) == false || screenshot_display_types.empty?
  fail!('metadata.screenshotDisplayTypes must be a non-empty array')
end

app_id = resolve_app_id!
version_id = resolve_version_id!(app_id, version_string)
localization_id = resolve_localization_id!(version_id, locale)

patch_localization!(localization_id, metadata)
puts JSON.pretty_generate(event: 'localization_patched', localizationId: localization_id)

source_screenshot_paths = Dir.glob(File.join(SCREENSHOTS_SOURCE_DIR, '*.{png,PNG,jpg,JPG,jpeg,JPEG}'))
assert_screenshot_files!(source_screenshot_paths)

screenshot_display_types.each do |display_type|
  screenshot_set_id = ensure_screenshot_set!(localization_id, display_type)
  puts JSON.pretty_generate(event: 'screenshot_set_ready', screenshotSetId: screenshot_set_id, displayType: display_type)

  generated_paths = generate_screenshots!(source_screenshot_paths, display_type)
  ensure_screenshots!(screenshot_set_id, generated_paths)
end

if metadata_file.key?('buildId')
  attach_build!(version_id, metadata_file.fetch('buildId'), metadata)
  puts JSON.pretty_generate(event: 'build_attached', versionId: version_id, buildId: metadata_file.fetch('buildId'))
end
