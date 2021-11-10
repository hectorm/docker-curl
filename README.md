# cURL

A statically linked build of [cURL](https://github.com/curl/curl) in a Docker container.

## Usage
```sh
docker run --rm hectormolinero/curl:latest --help
```

## Export build to local filesystem
```sh
docker pull hectormolinero/curl:latest
docker save hectormolinero/curl:latest | tar -xO --wildcards '*/layer.tar' | tar -xi curl ca-bundle.crt
```
