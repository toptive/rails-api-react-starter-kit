class Uploads::Guard
  KINDS = {
    "image" => { types: %w[image/jpeg image/png image/webp image/gif], max_bytes: 10_000_000 },
    "document" => { types: %w[application/pdf image/jpeg image/png], max_bytes: 20_000_000 },
    "avatar" => { types: %w[image/jpeg image/png image/webp], max_bytes: 2_000_000 }
  }.freeze

  def self.check!(kind, type, size)
    rule = KINDS[kind]
    raise ApiError.unprocessable(:unknown_kind) unless rule
    raise ApiError.unprocessable(:content_type_not_allowed) unless rule.fetch(:types).include?(type)
    raise ApiError.unprocessable(:invalid_size) unless size.is_a?(Integer) && size.positive?
    raise ApiError.unprocessable(:too_large) if size > rule.fetch(:max_bytes)
  end

  def self.safe_filename(filename)
    extension = File.extname(filename).downcase.gsub(/[^.a-z0-9]/, "")[0, 15]
    base = File.basename(filename, File.extname(filename)).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 60]
    "#{base.presence || 'file'}#{extension}"
  end

  def self.sniff(bytes)
    bytes = bytes.b
    return "image/jpeg" if bytes.start_with?("\xFF\xD8\xFF".b)
    return "image/png" if bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    return "image/gif" if bytes.start_with?("GIF87a", "GIF89a")
    return "image/webp" if bytes.start_with?("RIFF") && bytes[8, 4] == "WEBP"
    return "application/pdf" if bytes.start_with?("%PDF-")

    "application/octet-stream"
  end
end
