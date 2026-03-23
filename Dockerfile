ARG ERLANG_VERSION=28.4.2.0
ARG GLEAM_VERSION=v1.15.4
ARG TAILWINDCSS_VERSION=v3.4.19

# Get the Gleam binary
FROM ghcr.io/gleam-lang/gleam:${GLEAM_VERSION}-scratch AS gleam

FROM erlang:${ERLANG_VERSION}-alpine AS build
RUN apk add --no-cache git ca-certificates
COPY --from=gleam /bin/gleam /bin/gleam

ARG TAILWINDCSS_VERSION
ARG TARGETARCH
RUN TAILWIND_ARCH=$(case ${TARGETARCH} in arm64) echo "arm64";; *) echo "x64";; esac) && \
    wget -O /usr/local/bin/tailwindcss https://github.com/tailwindlabs/tailwindcss/releases/download/${TAILWINDCSS_VERSION}/tailwindcss-linux-${TAILWIND_ARCH} \
    && chmod +x /usr/local/bin/tailwindcss

COPY . /app/
WORKDIR /app

RUN cd shared && gleam build

RUN cd client && gleam build
RUN cd client && gleam run -m lustre/dev build --minify --no-html --outdir=../server/priv/static
RUN cp client/index.html server/priv/static/index.html

RUN /usr/local/bin/tailwindcss -i client/tailwind.css -o server/priv/static/styles.css --minify

RUN cd server && gleam build
RUN cd server && gleam export erlang-shipment

FROM erlang:${ERLANG_VERSION}-alpine
RUN apk add --no-cache shadow

ARG GIT_SHA
ARG BUILD_TIME
# RandomBytes = crypto:strong_rand_bytes(100).
# base64:encode_to_string(RandomBytes).
ARG ERLANG_COOKIE
ENV GIT_SHA=${GIT_SHA}
ENV BUILD_TIME=${BUILD_TIME}

RUN mkdir /app \
    && usermod -d /app guest \
    && chown guest /app \
    && echo "${ERLANG_COOKIE}" > /app/.erlang.cookie \
    && chown guest /app/.erlang.cookie \
    && chmod 400 /app/.erlang.cookie

USER guest
COPY --chown=guest --from=build /app/server/build/erlang-shipment /app
COPY --chown=guest --from=build /app/server/priv /app/priv

ENV HOME=/app
ENV ERL_FLAGS="-sname shoebill"
ENV HOST="0.0.0.0"
WORKDIR /app
EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
