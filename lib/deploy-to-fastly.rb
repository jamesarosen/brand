#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'singleton'
require 'uri'

UploadResult = Struct.new(:success, :message) do
  alias_method :success?, :success
end

class FastlyDictionaryItemUploader
  include Singleton

  def initialize
    @service_id = env_var 'FASTLY_SERVICE_ID'
    @dictionary_id = env_var 'FASTLY_BODIES_DICTIONARY_ID'
    @api_key = env_var 'FASTLY_API_KEY'
    @http = Net::HTTP.new 'api.fastly.com', '443'
    @http.use_ssl = true
  end

  def upload(fileToUpload)
    begin
      parse_response make_request(fileToUpload)
    rescue Exception => e
      UploadResult.new false, e.to_s
    end
  end

  private

  def env_var(key)
    ENV[key].tap do |value|
      raise "Set environment variable #{key}" if value.nil?
    end
  end

  def parse_response(response)
    code = response.code.to_i
    if (code >= 200 && code < 400)
      UploadResult.new true, 'Done'
    else
      message = begin
        JSON.parse(response.body)['msg'] || "Error #{response.code}"
      rescue Exception => e
        e.to_s
      end

      UploadResult.new false, message
    end
  end

  def make_request(fileToUpload)
    @http.start do |http|
      http.request put(fileToUpload)
    end
  end

  def put(fileToUpload)
    uri = dictionary_item_uri(fileToUpload)
    Net::HTTP::Put.new(uri.request_uri).tap do |req|
      req['Accept'] = 'application/json'
      req['Connection'] = 'close'
      req['Fastly-Key'] = @api_key
      req.set_form_data({
        'item_key' => fileToUpload.path,
        'item_value' => fileToUpload.contents
      })
    end
  end

  def dictionary_item_uri(fileToUpload)
    key = URI.encode fileToUpload.path, URI::REGEXP::PATTERN::RESERVED
    URI.parse "https://api.fastly.com/service/#{@service_id}/dictionary/#{@dictionary_id}/item/#{key}"
  end
end

FileToUpload = Struct.new(:path, :contents) do
  def self.all
    public_root = File.expand_path('../../public', __FILE__)

    Dir.glob("#{public_root}/**/*.*").map do |path|
      FileToUpload.new path.sub(public_root, ''), File.read(path)
    end
  end

  def upload
    FastlyDictionaryItemUploader.instance.upload self
  end

  def inspect
    "<#{path}>"
  end
end

FileToUpload.all.each do |f|
  result = f.upload
  prefix = result.success? ? '✓' : '✘'
  puts "#{prefix} #{f.path}: #{result.message}"
  exit 1 unless result.success?
end
