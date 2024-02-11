# cURL

A statically linked build of [cURL](https://github.com/curl/curl) in a Docker container.

## Usage
```sh
docker container run --rm docker.io/hectorm/curl:latest --help
```

## Export build to local filesystem
```sh
docker container export "$(docker container create docker.io/hectorm/curl:latest)" | tar -xi curl ca-bundle.crt
```
