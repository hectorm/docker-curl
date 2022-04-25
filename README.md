# cURL

A statically linked build of [cURL](https://github.com/curl/curl) in a Docker container.

## Usage
```sh
docker run --rm docker.io/hectorm/curl:latest --help
```

## Export build to local filesystem
```sh
docker pull docker.io/hectorm/curl:latest
docker save docker.io/hectorm/curl:latest | tar -xO --wildcards '*/layer.tar' | tar -xi curl ca-bundle.crt
```
