[![Build Status](https://drone.viktorbarzin.me/api/badges/ViktorBarzin/Website/status.svg)](https://drone.viktorbarzin.me/ViktorBarzin/Website)

# My personal blog

This repo contains the sources for my website:

https://viktorbarzin.me

# Building

The `Dockerfile` in the repo is used to build the website inside my Kubernetes cluster.

You will not be able to build it without the `LETSENCRYPT_PASS` variable which is the password for the letsencrypt dir

To build it run:

````bash
docker build --build-arg LETSENCRYPT_PASS="$LETSENCRYPT_PASS" -t viktorbarzin/blog .```
````
