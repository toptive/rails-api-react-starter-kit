# syntax=docker/dockerfile:1
# check=error=true
# Build from the repository root: docker build -t starter_kit:local .
ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=24

# The root manifest owns the SPA; use its exact pnpm version.
FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS frontend
WORKDIR /build
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN npm install --global "$(node -p 'require("./package.json").packageManager')" && \
    pnpm install --frozen-lockfile
COPY . .
# The output argument also works when the shared SPA is imported into this kit.
RUN pnpm build --outDir ../public --emptyOutDir

FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY vendor/ ./vendor/
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile
COPY . .
RUN bundle exec bootsnap precompile -j 1 app/ lib/
# Propshaft serves Mission Control; no production secret or database at build time.
RUN SPA_ORIGIN=https://build.invalid API_ORIGIN=https://build.invalid \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base AS production
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails
COPY --chown=rails:rails --from=frontend /build/public/ /rails/public/
RUN mkdir -p tmp/pids tmp/cache log storage && chown -R rails:rails tmp log storage
USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server", "-b", "0.0.0.0"]
