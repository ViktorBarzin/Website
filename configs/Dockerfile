# Install the latest Debain operating system.
FROM debian:latest as HUGO

# Password to decrypt letsencrypt tar. Specify as CLI arg to docker build
ARG LETSENCRYPT_PASS

# Install Hugo.
RUN apt-get update -y && apt-get install hugo gpg -y

# Copy the contents of the current working directory to the
# static-site directory.
COPY . /static-site

# Command Hugo to build the static site from the source files,
# setting the destination to the public directory.
RUN hugo -v --source=/static-site --destination=/static-site/public

# Decrypt the letsencrypt tar
# RUN sh -c "cd /static-site/configs/ && echo \"$LETSENCRYPT_PASS\" | gpg --no-tty --pinentry-mode loopback --command-fd 0 --batch --yes --decrypt letsencrypt.tar.gz.asc | tar xzvf -"

# Install NGINX, remove the default NGINX index.html file, and
# copy the built static site files to the NGINX html directory.
FROM byjg/nginx-extras:latest
COPY --from=HUGO /static-site/public/ /var/www/html/
COPY --from=HUGO /static-site/configs/nginx.conf /etc/nginx/
#COPY --from=HUGO /static-site/configs/letsencrypt /etc/letsencrypt # Uncomment if setting LE cert in container again
RUN mkdir -p /etc/letsencrypt/live/viktorbarzin.me/

# Instruct the container to listen for requests on port 80 (HTTP).
EXPOSE 80 443
