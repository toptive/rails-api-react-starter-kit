# syntax=docker/dockerfile:1
# check=error=true
ARG RUBY_VERSION=3.4.10
FROM node:24-slim AS frontend
WORKDIR /build
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN npm install --global pnpm@12.3.4 && pnpm install --frozen-lockfile
COPY frontend ./frontend
COPY i18n ./i18n
ARG VITE_API_URL=""
ARG VITE_PUBLIC_URL=https://CHANGE_ME.example.com
ARG VITE_SITE_INDEXING=0
ARG VITE_PRERENDER_API_URL=""
ENV VITE_OUT_DIR=../public
RUN pnpm build

FROM ruby:${RUBY_VERSION}-slim-bookworm AS base
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 libpq5 libreadline8 liblz4-1 libzstd1 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test LD_PRELOAD=/usr/local/lib/libjemalloc.so

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /usr/local/bundle/ruby/*/cache
RUN find /usr/local/bundle/ruby/*/gems -mindepth 2 -maxdepth 2 -type d \( -name test -o -name tests -o -name spec -o -name features -o -name doc -o -name docs -o -name rbi -o -name ext \) -prune -exec rm -rf '{}' + && \
    find /usr/local/bundle -type f \( -name '*.o' -o -name '*.a' \) -delete && \
    find /usr/local/bundle -type f -name '*.so' -exec strip --strip-unneeded '{}' + && \
    strip --strip-unneeded /usr/local/bundle/ruby/*/gems/thruster-*/exe/*/thrust
# Prebuilt native gems ship several Ruby ABIs; this image runs only the pinned ABI.
RUN ruby -rrbconfig -rfileutils -e 'abi = RbConfig::CONFIG.fetch("ruby_version").split(".").first(2).join("."); Dir.glob("/usr/local/bundle/ruby/*/gems/{nokogiri-*/lib/nokogiri,pg-*/lib}/[0-9]*").each { |path| FileUtils.rm_r(path) unless File.basename(path) == abi }'
COPY app ./app
COPY bin ./bin
COPY config ./config
COPY db ./db
COPY i18n/translations.csv ./i18n/translations.csv
COPY lib ./lib
COPY Rakefile config.ru ./
# Product branding (favicons, social images) lives under public/; the SPA build lands on top.
COPY public ./public
COPY --from=frontend /build/public ./public
# Precompile app code; assets:precompile warms the gems actually loaded at boot.
RUN bundle exec bootsnap precompile -j 1 app/ lib/
RUN SPA_ORIGIN=https://CHANGE_ME.example.com API_ORIGIN=https://CHANGE_ME.example.com \
    SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM base AS runtime
# Direct PostgreSQL tools avoid the distribution's Perl-based version wrapper.
COPY --from=build /usr/lib/postgresql/15/bin/psql /usr/lib/postgresql/15/bin/pg_dump /usr/lib/postgresql/15/bin/pg_restore /usr/local/bin/
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /rails /rails
RUN install -d -o rails -g rails tmp/pids log storage
USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0"]
