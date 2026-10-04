require "aws-sdk-s3"

class Uploads
  PUT_TTL = 600
  GET_TTL = 300

  def self.configured? = %w[S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY].all? { |key| ENV[key].present? }

  def self.client
    raise ApiError.unavailable(:uploads_not_configured) unless configured?

    Aws::S3::Client.new(region: ENV.fetch("S3_REGION", "us-east-1"),
      endpoint: ENV.fetch("S3_ENDPOINT", "https://s3.amazonaws.com"),
      credentials: Aws::Credentials.new(ENV.fetch("S3_ACCESS_KEY_ID"), ENV.fetch("S3_SECRET_ACCESS_KEY")),
      force_path_style: true, retry_limit: 0, http_open_timeout: 5, http_read_timeout: 5,
      request_checksum_calculation: "when_required", response_checksum_validation: "when_required")
  end

  def self.presign(scope, attributes)
    User::Input.validate!(attributes, string_fields: %i[filename content_type kind], required: %i[filename content_type byte_size kind])
    Guard.check!(attributes[:kind], attributes[:content_type], attributes[:byte_size])
    storage = client
    key = "uploads/#{scope.organization.id}/#{SecureRandom.uuid}/#{Guard.safe_filename(attributes[:filename])}"
    url = Aws::S3::Presigner.new(client: storage).presigned_url(:put_object, bucket: ENV.fetch("S3_BUCKET"), key: key,
      content_type: attributes[:content_type], content_length: attributes[:byte_size],
      expires_in: PUT_TTL, whitelist_headers: [ "content-length", "content-type" ])
    { url: url, key: key, method: "PUT", headers: { "content-type" => attributes[:content_type] } }
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError
    raise ApiError.unavailable(:uploads_not_configured)
  end

  def self.verify(scope, key, kind)
    raise ApiError.unprocessable(:upload_incomplete) unless owned?(scope, key) && Guard::KINDS.key?(kind)

    storage = client
    object = storage.head_object(bucket: ENV.fetch("S3_BUCKET"), key: key)
    cap = Guard::KINDS.fetch(kind).fetch(:max_bytes)
    raise ApiError.unprocessable(:upload_incomplete) unless object.content_length.is_a?(Integer) && object.content_length.between?(1, cap)

    head = storage.get_object(bucket: ENV.fetch("S3_BUCKET"), key: key, range: "bytes=0-4095").body.read(4096)
    type = Guard.sniff(head)
    raise ApiError.unprocessable(:upload_incomplete) unless Guard::KINDS.fetch(kind).fetch(:types).include?(type) && object.content_type == type

    true
  rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError
    raise ApiError.unprocessable(:upload_incomplete)
  end

  def self.url(scope, key)
    raise ApiError.not_found unless owned?(scope, key)

    Aws::S3::Presigner.new(client: client).presigned_url(:get_object, bucket: ENV.fetch("S3_BUCKET"), key: key, expires_in: GET_TTL)
  end

  def self.owned?(scope, key)
    scope&.organization&.persisted? && key.is_a?(String) &&
      key.match?(%r{\Auploads/#{Regexp.escape(scope.organization.id)}/[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}/[a-z0-9][a-z0-9.-]{0,99}\z}) &&
      !key.include?("..")
  end
  private_class_method :owned?
end
