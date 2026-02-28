# Stage 1: Build the static site with Hugo
FROM ghcr.io/gohugoio/hugo:v0.157.0 AS builder

COPY --chown=hugo:hugo . /project
# SOURCE_DATE_EPOCH is passed by the CI plugin and changes each build,
# ensuring the Hugo build step is never served from cache
ARG SOURCE_DATE_EPOCH
RUN hugo --minify --noBuildLock

# Stage 2: Serve with NGINX
FROM nginx:1.28-alpine

COPY --from=builder /project/public/ /var/www/html/
COPY --from=builder /project/configs/nginx.conf /etc/nginx/

EXPOSE 80
