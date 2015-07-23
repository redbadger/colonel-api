# Colonel API

A Docker compose set up that spins up a Sinatra [Colonel](https://github.com/Bskyb/colonel) API container and a container for each of it's two dependencies; Elasticsearch and Redis. The goal of this app is to allow applications not written in Ruby(Colonel is a Ruby gem) to use the Colonel via a RESTful interface.

### Run

With [Docker Compose](https://docs.docker.com/compose/) installed run:

```shell
docker-compose up
```

If your using Boot2Docker run `boot2docker ip` to get your VM's ip and the API endpoint will be at:

http://ip-from-Boot2Docker:8080
