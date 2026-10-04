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

FROM ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test LD_PRELOAD=/usr/local/lib/libjemalloc.so

FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /usr/local/bundle/ruby/*/cache && \
    bundle exec bootsnap precompile -j 1 --gemfile
COPY . .
COPY --from=frontend /build/public ./public
RUN bundle exec bootsnap precompile -j 1 app/ lib/
RUN SPA_ORIGIN=https://CHANGE_ME.example.com API_ORIGIN=https://CHANGE_ME.example.com \
    SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM base AS runtime
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /rails /rails
RUN mkdir -p tmp log storage && chown -R rails:rails tmp log storage
USER 1000:1000
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
