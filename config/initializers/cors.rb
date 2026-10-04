Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("PUBLIC_URL", "http://localhost:5173"),
      "capacitor://localhost", "ionic://localhost", "http://localhost"
    resource "/api/v1/*",
      headers: %w[Authorization Content-Type Accept-Language If-None-Match],
      expose: %w[ETag Retry-After],
      methods: %i[get post put delete options head],
      credentials: false
  end
end
