FROM nickblah/lua:5-luarocks-alpine

WORKDIR /app

RUN apk add --no-cache \
  git \
  build-base \
  zip \
  curl

COPY . .

RUN luarocks install busted
RUN luarocks install buildkite-test-collector

RUN apk del -r --purge --no-cache \
  git \
  build-base
