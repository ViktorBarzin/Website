# Stage 1: Build the static site with Hugo
FROM ghcr.io/gohugoio/hugo:v0.157.0 AS builder

COPY . /src
RUN hugo --minify --noBuildLock --source=/src --destination=/src/public

# Stage 2: Serve with NGINX
FROM nginx:1.28-alpine

COPY --from=builder /src/public/ /var/www/html/
COPY --from=builder /src/configs/nginx.conf /etc/nginx/

EXPOSE 80
