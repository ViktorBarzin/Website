# Stage 1: Build the static site with Hugo
FROM ghcr.io/gohugoio/hugo:v0.157.0 AS builder

COPY --chown=hugo:hugo . /project
RUN hugo --minify --noBuildLock

# Stage 2: Serve with NGINX
FROM nginx:1.28-alpine

COPY --from=builder /project/public/ /var/www/html/
COPY --from=builder /project/configs/nginx.conf /etc/nginx/

EXPOSE 80
