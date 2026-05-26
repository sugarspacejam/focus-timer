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
CONFIG_PATH = File.join(__dir__, 'release_config.json')

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

def request(method, path, body: nil, headers: {}, version: nil)
  if path.start_with?('/') == false
    fail!('PATH must start with /')
  end

  uri = URI.join(BASE_URL, path)
  if version
    uri = URI.join(BASE_URL, "/v#{version}#{path}")
  end

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

def load_config!
  if File.exist?(CONFIG_PATH) == false
    fail!("Missing config file: #{CONFIG_PATH}")
  end
  JSON.parse(File.read(CONFIG_PATH))
end

def resolve_app_id!(bundle_id)
  data = get_json!("/v1/apps?filter[bundleId]=#{bundle_id}")
  apps = data.fetch('data')
  if apps.length != 1
    fail!("Expected exactly 1 app for bundle id #{bundle_id}, got #{apps.length}")
  end
  apps.first.fetch('id')
end

def resolve_editable_app_info_id!(app_id)
  data = get_json!("/v1/apps/#{app_id}/appInfos")
  infos = data.fetch('data')
  match = infos.find do |info|
    attrs = info.fetch('attributes')
    attrs.fetch('state') == 'PREPARE_FOR_SUBMISSION' && attrs.fetch('appStoreState') == 'PREPARE_FOR_SUBMISSION'
  end

  if match.nil?
    fail!("Could not find editable appInfo for app #{app_id}")
  end

  match.fetch('id')
end

def resolve_app_info_localization_id!(app_info_id, locale)
  data = get_json!("/v1/appInfos/#{app_info_id}/appInfoLocalizations")
  locs = data.fetch('data')
  match = locs.find { |l| l.fetch('attributes').fetch('locale') == locale }

  if match.nil?
    fail!("Could not find appInfoLocalization #{locale} for appInfo #{app_info_id}")
  end

  match.fetch('id')
end

def update_app_info!(app_id, config)
  app_info_id = resolve_editable_app_info_id!(app_id)
  app_info_localization_id = resolve_app_info_localization_id!(app_info_id, config['app']['locale'])
  
  branding = config['branding']
  payload = {
    data: {
      type: 'appInfoLocalizations',
      id: app_info_localization_id,
      attributes: {
        name: branding['name'],
        subtitle: branding['subtitle']
      }
    }
  }
  
  result = patch_json!("/v1/appInfoLocalizations/#{app_info_localization_id}", payload)
  puts JSON.pretty_generate(event: 'app_info_updated', name: branding['name'], subtitle: branding['subtitle'])
  result
end

def update_localization!(app_id, version_string, locale, config)
  data = get_json!("/v1/apps/#{app_id}/appStoreVersions")
  versions = data.fetch('data')
  match = versions.find { |v| v.fetch('attributes').fetch('versionString') == version_string && v.fetch('attributes').fetch('platform') == 'IOS' }
  
  if match.nil?
    fail!("Could not find IOS appStoreVersion #{version_string} for app #{app_id}")
  end
  
  version_id = match.fetch('id')
  
  data = get_json!("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations")
  locs = data.fetch('data')
  match = locs.find { |l| l.fetch('attributes').fetch('locale') == locale }
  
  if match.nil?
    fail!("Could not find localization #{locale} for version #{version_id}")
  end
  
  localization_id = match.fetch('id')
  storefront = config['storefront']
  
  payload = {
    data: {
      type: "appStoreVersionLocalizations",
      id: localization_id,
      attributes: {
        promotionalText: storefront["promotionalText"],
        description: storefront["description"],
        keywords: storefront["keywords"],
        supportUrl: storefront["supportUrl"],
        marketingUrl: storefront["marketingUrl"]
      }
    }
  }
  
  result = patch_json!("/v1/appStoreVersionLocalizations/#{localization_id}", payload)
  puts JSON.pretty_generate(event: 'localization_updated', version: version_string, locale: locale)
  result
end

def create_iap!(app_id, config)
  iap_config = config['iap']
  payload = {
    data: {
      type: "inAppPurchases",
      attributes: {
        name: iap_config['name'],
        productId: iap_config['productId'],
        inAppPurchaseType: iap_config['type']
      },
      relationships: {
        app: {
          data: {
            type: "apps",
            id: app_id
          }
        }
      }
    }
  }
  
  res = request('POST', '/inAppPurchases', body: JSON.generate(payload), version: 2)
  if res[:status] >= 300
    fail!("POST /v2/inAppPurchases failed: #{res[:status]} #{res[:raw_body]}")
  end
  iap_id = res[:body].fetch('data').fetch('id')
  
  puts JSON.pretty_generate(event: 'iap_created', productId: iap_config['productId'], iapId: iap_id)
  res[:body]
end

def set_iap_price!(iap_id, config)
  pricing = config['pricing']
  target_price = pricing['iapPrice'].to_f
  
  # Get all price points for USA
  price_point_data = get_json!("/v2/inAppPurchases/#{iap_id}/pricePoints?filter[territory]=USA&limit=1000")
  price_points = price_point_data.fetch('data')
  
  # Find price point matching target price
  price_point = price_points.find { |pp| pp.fetch('attributes').fetch('customerPrice').to_f == target_price }
  if price_point.nil?
    fail!("Price point for $#{target_price} not found for USA territory")
  end
  price_point_id = price_point.fetch('id')
  
  # Create price schedule
  payload = {
    data: {
      type: "inAppPurchasePriceSchedules",
      relationships: {
        inAppPurchase: {
          data: {
            type: "inAppPurchases",
            id: iap_id
          }
        },
        manualPrices: [
          {
            type: "inAppPurchasePrices",
            id: "${price0}"
          }
        ]
      }
    },
    included: [
      {
        type: "inAppPurchasePrices",
        id: "${price0}",
        attributes: {
          startDate: nil
        },
        relationships: {
          inAppPurchaseV2: {
            data: {
              type: "inAppPurchasesV2",
              id: iap_id
            }
          },
          inAppPurchasePricePoint: {
            data: {
              type: "inAppPurchasePricePoints",
              id: price_point_id
            }
          }
        }
      }
    ]
  }
  
  res = request('POST', '/inAppPurchasePriceSchedules', body: JSON.generate(payload), version: 2)
  if res[:status] >= 300
    fail!("POST /v2/inAppPurchasePriceSchedules failed: #{res[:status]} #{res[:raw_body]}")
  end
  puts JSON.pretty_generate(event: 'iap_price_set', price: target_price, pricePointId: price_point_id)
  res[:body]
end

def create_app_version!(app_id, version_string, config)
  data = get_json!("/v1/apps/#{app_id}/appStoreVersions")
  versions = data.fetch('data')
  
  existing = versions.find { |v| v.fetch('attributes').fetch('versionString') == version_string }
  if existing
    puts JSON.pretty_generate(event: 'app_version_exists', version: version_string, id: existing.fetch('id'))
    return existing
  end
  
  payload = {
    data: {
      type: "appStoreVersions",
      attributes: {
        platform: "IOS",
        versionString: version_string,
        copyright: config['storefront']['copyright']
      },
      relationships: {
        app: {
          data: {
            type: "apps",
            id: app_id
          }
        }
      }
    }
  }
  
  result = post_json!('/v1/appStoreVersions', payload)
  puts JSON.pretty_generate(event: 'app_version_created', version: version_string)
  result
end

def attach_iap_to_version!(version_id, iap_id)
  payload = {
    data: {
      type: "inAppPurchasesV2",
      id: iap_id
    }
  }
  
  result = patch_json!("/v1/appStoreVersions/#{version_id}/relationships/inAppPurchasesV2", payload)
  puts JSON.pretty_generate(event: 'iap_attached_to_version', versionId: version_id, iapId: iap_id)
  result
end

def set_app_price!(app_id, config)
  pricing = config['pricing']
  target_price = pricing['appPrice'].to_f
  
  # Get app price points
  data = get_json!("/v2/apps/#{app_id}/appStoreVersions?filter[platform]=IOS&limit=10")
  versions = data.fetch('data')
  latest_version = versions.find { |v| v.fetch('attributes').fetch('appStoreState') == 'PREPARE_FOR_SUBMISSION' }
  
  if latest_version.nil?
    fail!("No version in PREPARE_FOR_SUBMISSION state found for app #{app_id}")
  end
  
  version_id = latest_version.fetch('id')
  
  # Get price points for the version
  price_point_data = get_json!("/v2/appStoreVersions/#{version_id}/pricePoints?filter[territory]=USA&limit=1000")
  price_points = price_point_data.fetch('data')
  
  # Find price point matching target price
  price_point = price_points.find { |pp| pp.fetch('attributes').fetch('customerPrice').to_f == target_price }
  if price_point.nil?
    fail!("Price point for $#{target_price} not found for USA territory")
  end
  price_point_id = price_point.fetch('id')
  
  # Create price schedule for app
  payload = {
    data: {
      type: "appStoreVersionPriceSchedules",
      relationships: {
        appStoreVersion: {
          data: {
            type: "appStoreVersions",
            id: version_id
          }
        },
        manualPrices: [{
          type: "appStoreVersionPrices",
          id: "manual-price-#{Time.now.to_i}"
        }]
      },
      included: [{
        type: "appStoreVersionPrices",
        id: "manual-price-#{Time.now.to_i}",
        attributes: {
          startDate: nil
        },
        relationships: {
          appStoreVersion: {
            data: {
              type: "appStoreVersions",
              id: version_id
            }
          },
          appStoreVersionPricePoint: {
            data: {
              type: "appStoreVersionPricePoints",
              id: price_point_id
            }
          }
        }
      }]
    }
  }
  
  res = request('POST', '/appStoreVersionPriceSchedules', body: JSON.generate(payload), version: 2)
  if res[:status] >= 300
    fail!("POST /v2/appStoreVersionPriceSchedules failed: #{res[:status]} #{res[:raw_body]}")
  end
  puts JSON.pretty_generate(event: 'app_price_set', price: target_price, pricePointId: price_point_id)
  res[:body]
end

def submit_for_review!(app_id, config)
  data = get_json!("/v1/apps/#{app_id}/appStoreVersions")
  versions = data.fetch('data')
  version = versions.find { |v| v.fetch('attributes').fetch('appStoreState') == 'PREPARE_FOR_SUBMISSION' }
  
  if version.nil?
    fail!("No version in PREPARE_FOR_SUBMISSION state found for app #{app_id}")
  end
  
  version_id = version.fetch('id')
  
  # Check if build is attached
  build_id = version.dig('relationships', 'build', 'data', 'id')
  if build_id.nil?
    fail!("No build attached to version #{version_id}. Upload a build first.")
  end
  
  payload = {
    data: {
      type: "appStoreVersionSubmissions",
      attributes: {},
      relationships: {
        appStoreVersion: {
          data: {
            type: "appStoreVersions",
            id: version_id
          }
        }
      }
    }
  }
  
  result = post_json!("/v1/appStoreVersionSubmissions", payload)
  puts JSON.pretty_generate(event: 'submitted_for_review', versionId: version_id, buildId: build_id)
  result
end

config = load_config!
app_id = resolve_app_id!(config['app']['bundleId'])

steps = config['steps']
steps.each do |step|
  case step
  when 'update_app_info'
    update_app_info!(app_id, config)
  when 'update_localization'
    update_localization!(app_id, config['app']['versionString'], config['app']['locale'], config)
  when 'create_iap'
    iap_result = create_iap!(app_id, config)
    config['iap_id'] = iap_result.fetch('data').fetch('id')
  when 'set_iap_price'
    iap_id = config['iap_id']
    if iap_id.nil?
      fail!("IAP ID not found - create_iap step must run before set_iap_price, or set iap_id in config")
    end
    set_iap_price!(iap_id, config)
  when 'create_app_version'
    data = get_json!("/v1/apps/#{app_id}/appStoreVersions")
    puts JSON.pretty_generate(event: 'current_versions', data: data)
    version_result = create_app_version!(app_id, config['app']['versionString'], config)
    config['version_id'] = version_result.fetch('data').fetch('id')
  when 'attach_iap_to_version'
    if config['version_id'].nil? || config['iap_id'].nil?
      fail!("Version ID and IAP ID required - create_app_version and create_iap must run first")
    end
    attach_iap_to_version!(config['version_id'], config['iap_id'])
  when 'set_app_price'
    set_app_price!(app_id, config)
  when 'submit_for_review'
    submit_for_review!(app_id, config)
  else
    fail!("Unknown step: #{step}")
  end
end

puts JSON.pretty_generate(event: 'release_complete', app_id: app_id, version: config['app']['versionString'])
