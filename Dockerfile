# syntax=docker/dockerfile:1
FROM ruby:4.0.8-slim-trixie AS ruby
RUN apt-get update && apt-get install --no-install-recommends -y build-essential libyaml-dev libsqlite3-dev git && rm -rf /var/lib/apt/lists/*
RUN gem install bundler -v 4.0.23 --no-document
ENV BUNDLE_PATH=/usr/local/bundle
WORKDIR /app

FROM ruby AS gems
COPY Gemfile Gemfile.lock* ./
RUN bundle install
RUN json_gem="$(bundle exec ruby -e 'print Gem::Specification.find_by_name("json").cache_file')" \
    && gem install --local "$json_gem" --install-dir /usr/local/bundle --no-document

FROM ruby:4.0.8-slim-trixie AS runtime
ENV BUNDLE_PATH=/usr/local/bundle
COPY --from=gems /usr/local/bundle /usr/local/bundle
RUN <<'SHELL'
set -eu
ruby -rfileutils -rrbconfig <<'RUBY'
Gem::Specification.select { |spec| spec.name == "json" && spec.default_gem? }.each do |spec|
  FileUtils.rm_f(spec.loaded_from)
  FileUtils.rm_rf(spec.full_gem_path)
end
%w[rubylibdir archdir].each do |key|
  %w[json json.rb].each do |name|
    FileUtils.rm_rf(File.join(RbConfig::CONFIG.fetch(key), name))
  end
end
RUBY
useradd --create-home --uid 1000 app
SHELL
WORKDIR /app
COPY --chown=app:app . .
RUN test "$(ruby -rjson -e 'print JSON::VERSION')" = "$(bundle exec ruby -rjson -e 'print JSON::VERSION')" \
    && mkdir -p storage tmp/pids log && chown -R app:app storage tmp log
USER app
EXPOSE 8765
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "8765"]

FROM gems AS test
RUN useradd --create-home --uid 1000 app
COPY --from=runtime --chown=app:app /app /app
USER app
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/check"]

FROM runtime AS app
