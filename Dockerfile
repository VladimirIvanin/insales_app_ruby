# syntax=docker/dockerfile:1
FROM ruby:4.0.8-slim-trixie AS ruby
RUN apt-get update && apt-get install --no-install-recommends -y build-essential libyaml-dev libsqlite3-dev git && rm -rf /var/lib/apt/lists/*
RUN gem install bundler -v 4.0.23 --no-document
ENV BUNDLE_PATH=/usr/local/bundle
WORKDIR /app

FROM ruby AS gems
COPY Gemfile Gemfile.lock* ./
RUN bundle install

FROM debian:trixie-slim AS app
RUN apt-get update && apt-get install --no-install-recommends -y ca-certificates libssl3t64 libyaml-0-2 zlib1g libgmp10 libffi8 libsqlite3-0 git && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 app
COPY --from=gems /usr/local/ /usr/local/
ENV GEM_HOME=/usr/local/bundle BUNDLE_PATH=/usr/local/bundle PATH=/usr/local/bundle/bin:/usr/local/bin:$PATH
WORKDIR /app
COPY --chown=app:app . .
RUN mkdir -p storage tmp/pids log && chown -R app:app storage tmp log
USER app
EXPOSE 8765
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "8765"]
